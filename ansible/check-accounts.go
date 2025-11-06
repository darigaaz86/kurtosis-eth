package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"math/big"
	"os"
	"sync"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

type Account struct {
	Address    string `json:"address"`
	PrivateKey string `json:"private_key"`
}

type AccountStatus struct {
	Address      string
	Balance      string
	Nonce        uint64
	PendingNonce uint64
	HasBalance   bool
}

func main() {
	rpcEndpoint := flag.String("rpc", "http://localhost:8545", "RPC endpoint")
	addressFile := flag.String("addresses", "addresses.json", "Path to address file")
	flag.Parse()

	accounts, err := loadAccounts(*addressFile)
	if err != nil {
		log.Fatalf("Failed to load accounts: %v", err)
	}

	log.Printf("Loaded %d accounts", len(accounts))
	log.Printf("Connecting to %s", *rpcEndpoint)

	client, err := ethclient.Dial(*rpcEndpoint)
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer client.Close()

	ctx := context.Background()

	var wg sync.WaitGroup
	var mu sync.Mutex

	statuses := make([]AccountStatus, len(accounts))
	zeroBalance := 0
	withBalance := 0
	nonZeroNonce := 0

	batchSize := 100
	for i := 0; i < len(accounts); i += batchSize {
		end := i + batchSize
		if end > len(accounts) {
			end = len(accounts)
		}

		for j := i; j < end; j++ {
			wg.Add(1)
			go func(idx int, account Account) {
				defer wg.Done()

				addr := common.HexToAddress(account.Address)

				balance, err := client.BalanceAt(ctx, addr, nil)
				if err != nil {
					return
				}

				nonce, err := client.NonceAt(ctx, addr, nil)
				if err != nil {
					return
				}

				pendingNonce, err := client.PendingNonceAt(ctx, addr)
				if err != nil {
					pendingNonce = nonce
				}

				hasBalance := balance.Cmp(big.NewInt(0)) > 0

				mu.Lock()
				statuses[idx] = AccountStatus{
					Address:      account.Address,
					Balance:      balance.String(),
					Nonce:        nonce,
					PendingNonce: pendingNonce,
					HasBalance:   hasBalance,
				}
				if hasBalance {
					withBalance++
				} else {
					zeroBalance++
				}
				if nonce > 0 {
					nonZeroNonce++
				}
				mu.Unlock()
			}(j, accounts[j])
		}

		wg.Wait()

		if (i+batchSize)%1000 == 0 {
			log.Printf("Progress: checked %d/%d accounts", i+batchSize, len(accounts))
		}
	}

	log.Println("\n=== Summary ===")
	log.Printf("Total accounts: %d", len(accounts))
	log.Printf("With balance: %d", withBalance)
	log.Printf("Zero balance: %d", zeroBalance)
	log.Printf("Non-zero nonce: %d", nonZeroNonce)

	// Print all accounts
	log.Println("\n=== All Accounts ===")
	for i, status := range statuses {
		balanceEth := new(big.Int)
		balanceEth.SetString(status.Balance, 10)
		balanceFloat := new(big.Float).SetInt(balanceEth)
		balanceFloat.Quo(balanceFloat, big.NewFloat(1e18))

		log.Printf("[%d] %s: balance=%s ETH, nonce=%d, pending=%d",
			i, status.Address, balanceFloat.Text('f', 6), status.Nonce, status.PendingNonce)
	}

	// Show accounts with nonce gaps
	log.Println("\n=== Accounts with Nonce Gaps ===")
	gapCount := 0
	for _, status := range statuses {
		if status.PendingNonce > status.Nonce {
			log.Printf("%s: nonce=%d, pending=%d, gap=%d",
				status.Address, status.Nonce, status.PendingNonce, status.PendingNonce-status.Nonce)
			gapCount++
		}
	}
	if gapCount == 0 {
		log.Println("No nonce gaps found")
	}
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
