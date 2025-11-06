package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"flag"
	"log"
	"math/big"
	"os"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type Account struct {
	Address    string `json:"address"`
	PrivateKey string `json:"private_key"`
}

type Config struct {
	RpcEndpoint string
	AddressFile string
	ChainID     int64
	GasPrice    int64
	GasLimit    uint64
	MaxGapSize  int
	DryRun      bool
}

func main() {
	config := parseFlags()

	accounts, err := loadAccounts(config.AddressFile)
	if err != nil {
		log.Fatalf("Failed to load accounts: %v", err)
	}

	log.Printf("Loaded %d accounts", len(accounts))
	log.Printf("Connecting to %s", config.RpcEndpoint)

	client, err := ethclient.Dial(config.RpcEndpoint)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer client.Close()

	ctx := context.Background()
	chainID := big.NewInt(config.ChainID)
	gasPrice := big.NewInt(config.GasPrice)

	log.Println("Scanning for nonce gaps...")

	var wg sync.WaitGroup
	var mu sync.Mutex
	totalGaps := 0
	totalFilled := 0

	// Process accounts in batches
	batchSize := 100
	for i := 0; i < len(accounts); i += batchSize {
		end := i + batchSize
		if end > len(accounts) {
			end = len(accounts)
		}

		for j := i; j < end; j++ {
			wg.Add(1)
			go func(account Account) {
				defer wg.Done()

				addr := common.HexToAddress(account.Address)

				// Get current nonce from chain
				currentNonce, err := client.NonceAt(ctx, addr, nil)
				if err != nil {
					return
				}

				// Get pending nonce (includes pending txs)
				pendingNonce, err := client.PendingNonceAt(ctx, addr)
				if err != nil {
					return
				}

				// Check if there's a gap
				if pendingNonce > currentNonce {
					gap := int(pendingNonce - currentNonce)

					mu.Lock()
					totalGaps++
					mu.Unlock()

					if gap > config.MaxGapSize {
						log.Printf("Large gap detected for %s: current=%d, pending=%d, gap=%d (skipping)",
							addr.Hex(), currentNonce, pendingNonce, gap)
						return
					}

					log.Printf("Gap found for %s: current=%d, pending=%d, gap=%d",
						addr.Hex(), currentNonce, pendingNonce, gap)

					if config.DryRun {
						mu.Lock()
						totalFilled += gap
						mu.Unlock()
						return
					}

					// Fill the gap by sending transactions for missing nonces
					key, err := crypto.HexToECDSA(account.PrivateKey)
					if err != nil {
						log.Printf("Invalid key for %s: %v", addr.Hex(), err)
						return
					}

					filled := fillGap(ctx, client, key, addr, currentNonce, pendingNonce, chainID, gasPrice, config.GasLimit)

					mu.Lock()
					totalFilled += filled
					mu.Unlock()
				}
			}(accounts[j])
		}

		wg.Wait()

		if (i+batchSize)%1000 == 0 {
			log.Printf("Progress: checked %d/%d accounts", i+batchSize, len(accounts))
		}
	}

	log.Println("\n=== Summary ===")
	log.Printf("Total accounts checked: %d", len(accounts))
	log.Printf("Accounts with gaps: %d", totalGaps)
	log.Printf("Nonces filled: %d", totalFilled)
	if config.DryRun {
		log.Println("DRY RUN - No transactions were sent")
	}
}

func fillGap(ctx context.Context, client *ethclient.Client, key *ecdsa.PrivateKey,
	addr common.Address, currentNonce, pendingNonce uint64,
	chainID, gasPrice *big.Int, gasLimit uint64) int {

	filled := 0

	// Send transactions for each missing nonce
	for nonce := currentNonce; nonce < pendingNonce; nonce++ {
		// Send to self with 0 value (just to fill the gap)
		amount := big.NewInt(0)
		tx := types.NewTransaction(nonce, addr, amount, gasLimit, gasPrice, nil)

		signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), key)
		if err != nil {
			log.Printf("Failed to sign tx for %s nonce %d: %v", addr.Hex(), nonce, err)
			continue
		}

		err = client.SendTransaction(ctx, signedTx)
		if err != nil {
			log.Printf("Failed to send tx for %s nonce %d: %v", addr.Hex(), nonce, err)
			continue
		}

		filled++
		log.Printf("Filled gap: %s nonce %d", addr.Hex(), nonce)
	}

	return filled
}

func parseFlags() Config {
	config := Config{}

	flag.StringVar(&config.RpcEndpoint, "rpc", "http://localhost:8545", "RPC endpoint")
	flag.StringVar(&config.AddressFile, "addresses", "addresses.json", "Path to address file")
	flag.Int64Var(&config.ChainID, "chain-id", 1, "Chain ID")
	flag.Int64Var(&config.GasPrice, "gas-price", 20000000000, "Gas price in wei")
	flag.Uint64Var(&config.GasLimit, "gas-limit", 21000, "Gas limit")
	flag.IntVar(&config.MaxGapSize, "max-gap", 100, "Maximum gap size to fill (safety limit)")
	flag.BoolVar(&config.DryRun, "dry-run", false, "Dry run - only detect gaps, don't fill")

	flag.Parse()

	return config
}

func loadAccounts(filename string) ([]Account, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var accounts []Account
	err = json.Unmarshal(data, &accounts)
	if err != nil {
		return nil, err
	}

	return accounts, nil
}
