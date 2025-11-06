package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/big"
	"math/rand"
	"os"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type Config struct {
	TargetTPS   int
	Duration    int
	Endpoints   []string
	AddressFile string
	FunderKeys  []string
	FundAmount  string
	ChainID     int64
	GasPrice    int64
	GasLimit    uint64
	SkipFunding bool
}

type Account struct {
	Address    string `json:"address"`
	PrivateKey string `json:"private_key"`
}

func main() {
	config := parseFlags()

	accounts, err := loadAccounts(config.AddressFile)
	if err != nil {
		log.Fatalf("Failed to load accounts: %v", err)
	}

	log.Printf("Loaded %d accounts", len(accounts))
	log.Printf("Using %d endpoints and %d funders", len(config.Endpoints), len(config.FunderKeys))

	// Step 1: Fund accounts if needed
	if !config.SkipFunding && len(config.FunderKeys) > 0 {
		log.Println("Starting parallel funding phase...")
		err = fundAccountsParallel(config, accounts)
		if err != nil {
			log.Fatalf("Failed to fund accounts: %v", err)
		}
		log.Println("Funding phase completed")
	}

	// Step 2: Run TPS test
	log.Printf("Starting TPS test: %d TPS for %d seconds", config.TargetTPS, config.Duration)
	runTPSTest(config, accounts)
}

func parseFlags() Config {
	config := Config{}

	var endpointsStr, fundersStr string

	flag.IntVar(&config.TargetTPS, "tps", 1000, "Target transactions per second")
	flag.IntVar(&config.Duration, "duration", 60, "Test duration in seconds")
	flag.StringVar(&endpointsStr, "endpoints", "http://localhost:8545", "Comma-separated RPC endpoints")
	flag.StringVar(&config.AddressFile, "addresses", "addresses.json", "Path to address file")
	flag.StringVar(&fundersStr, "funders", "", "Comma-separated private keys of pre-funded accounts")
	flag.StringVar(&config.FundAmount, "fund-amount", "1000000000000000000", "Amount to fund each address (wei)")
	flag.Int64Var(&config.ChainID, "chain-id", 1, "Chain ID")
	flag.Int64Var(&config.GasPrice, "gas-price", 20000000000, "Gas price in wei")
	flag.Uint64Var(&config.GasLimit, "gas-limit", 21000, "Gas limit for transactions")
	flag.BoolVar(&config.SkipFunding, "skip-funding", false, "Skip funding phase")

	flag.Parse()

	// Parse comma-separated values
	if endpointsStr != "" {
		for _, ep := range splitAndTrim(endpointsStr, ",") {
			if ep != "" {
				config.Endpoints = append(config.Endpoints, ep)
			}
		}
	}

	if fundersStr != "" {
		for _, fk := range splitAndTrim(fundersStr, ",") {
			if fk != "" {
				config.FunderKeys = append(config.FunderKeys, fk)
			}
		}
	}

	return config
}

func splitAndTrim(s, sep string) []string {
	var result []string
	for _, item := range splitString(s, sep) {
		trimmed := trimSpace(item)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

func splitString(s, sep string) []string {
	if s == "" {
		return nil
	}
	var result []string
	start := 0
	for i := 0; i < len(s); i++ {
		if string(s[i]) == sep {
			result = append(result, s[start:i])
			start = i + 1
		}
	}
	result = append(result, s[start:])
	return result
}

func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
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

func containsAny(s string, substrs []string) bool {
	for _, substr := range substrs {
		if len(s) >= len(substr) {
			for i := 0; i <= len(s)-len(substr); i++ {
				if s[i:i+len(substr)] == substr {
					return true
				}
			}
		}
	}
	return false
}

func fundAccountsParallel(config Config, accounts []Account) error {
	numFunders := len(config.FunderKeys)
	numEndpoints := len(config.Endpoints)

	if numFunders == 0 || numEndpoints == 0 {
		return fmt.Errorf("no funders or endpoints provided")
	}

	// Divide accounts among funders
	accountsPerFunder := len(accounts) / numFunders
	remainder := len(accounts) % numFunders

	var wg sync.WaitGroup
	var mu sync.Mutex
	totalFunded := 0
	totalSkipped := 0

	for funderIdx := 0; funderIdx < numFunders; funderIdx++ {
		start := funderIdx * accountsPerFunder
		end := start + accountsPerFunder
		if funderIdx == numFunders-1 {
			end += remainder
		}

		funderAccounts := accounts[start:end]
		funderKey := config.FunderKeys[funderIdx]
		endpoint := config.Endpoints[funderIdx%numEndpoints]

		wg.Add(1)
		go func(idx int, key string, ep string, accts []Account) {
			defer wg.Done()

			funded, skipped := fundWithFunder(config, key, ep, accts, idx)

			mu.Lock()
			totalFunded += funded
			totalSkipped += skipped
			mu.Unlock()
		}(funderIdx, funderKey, endpoint, funderAccounts)
	}

	wg.Wait()

	log.Printf("Total funding complete: funded %d, skipped %d", totalFunded, totalSkipped)
	log.Println("Waiting 5 seconds for transactions to be mined...")
	time.Sleep(5 * time.Second)

	return nil
}

func fundWithFunder(config Config, funderKeyHex string, endpoint string, accounts []Account, funderIdx int) (int, int) {
	client, err := ethclient.Dial(endpoint)
	if err != nil {
		log.Printf("Funder %d: Failed to connect to %s: %v", funderIdx, endpoint, err)
		return 0, 0
	}
	defer client.Close()

	funderKey, err := crypto.HexToECDSA(funderKeyHex)
	if err != nil {
		log.Printf("Funder %d: Invalid key: %v", funderIdx, err)
		return 0, 0
	}

	funderAddr := crypto.PubkeyToAddress(funderKey.PublicKey)
	log.Printf("Funder %d (%s): Processing %d accounts", funderIdx, funderAddr.Hex(), len(accounts))

	fundAmount := new(big.Int)
	fundAmount.SetString(config.FundAmount, 10)

	ctx := context.Background()
	nonce, err := client.PendingNonceAt(ctx, funderAddr)
	if err != nil {
		log.Printf("Funder %d: Failed to get nonce: %v", funderIdx, err)
		return 0, 0
	}

	gasPrice := big.NewInt(config.GasPrice)
	chainID := big.NewInt(config.ChainID)

	funded := 0
	skipped := 0
	failed := 0

	for i, account := range accounts {
		addr := common.HexToAddress(account.Address)

		// Check balance - skip if account has sufficient balance (>= 0.5 ETH)
		balance, err := client.BalanceAt(ctx, addr, nil)
		if err != nil {
			log.Printf("Funder %d: Failed to get balance for %s: %v", funderIdx, addr.Hex(), err)
			failed++
			continue
		}

		minBalance := new(big.Int)
		minBalance.SetString("500000000000000000", 10) // 0.5 ETH
		if balance.Cmp(minBalance) >= 0 {
			skipped++
			continue
		}

		// Fund the account
		tx := types.NewTransaction(nonce, addr, fundAmount, config.GasLimit, gasPrice, nil)
		signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), funderKey)
		if err != nil {
			log.Printf("Funder %d: Failed to sign tx for %s: %v", funderIdx, addr.Hex(), err)
			failed++
			continue
		}

		err = client.SendTransaction(ctx, signedTx)
		if err != nil {
			log.Printf("Funder %d: Failed to send tx for %s (nonce %d): %v", funderIdx, addr.Hex(), nonce, err)
			failed++
			continue
		}

		nonce++
		funded++

		if (i+1)%500 == 0 {
			log.Printf("Funder %d: Progress %d/%d (funded: %d, skipped: %d)", funderIdx, i+1, len(accounts), funded, skipped)
		}
	}

	log.Printf("Funder %d: Complete - funded %d, skipped %d, failed %d", funderIdx, funded, skipped, failed)
	return funded, skipped
}

func runTPSTest(config Config, accounts []Account) {
	if len(config.Endpoints) == 0 {
		log.Fatal("No endpoints provided")
	}

	// Create clients for all endpoints
	clients := make([]*ethclient.Client, len(config.Endpoints))
	for i, endpoint := range config.Endpoints {
		client, err := ethclient.Dial(endpoint)
		if err != nil {
			log.Fatalf("Failed to connect to endpoint %s: %v", endpoint, err)
		}
		clients[i] = client
		defer client.Close()
	}
	log.Printf("Connected to %d endpoint(s)", len(clients))

	ctx := context.Background()
	chainID := big.NewInt(config.ChainID)
	gasPrice := big.NewInt(config.GasPrice)

	// Prepare account keys and fetch current nonces
	keys := make([]*ecdsa.PrivateKey, len(accounts))
	nonces := make([]uint64, len(accounts))

	log.Println("Preparing account keys and fetching nonces in parallel...")

	// Prepare keys first (fast, no network calls)
	for i, account := range accounts {
		key, err := crypto.HexToECDSA(account.PrivateKey)
		if err != nil {
			log.Fatalf("Invalid private key for account %d: %v", i, err)
		}
		keys[i] = key
	}
	log.Printf("Keys prepared for %d accounts", len(accounts))

	// Fetch nonces in parallel batches
	var nonceWg sync.WaitGroup
	var nonceMu sync.Mutex
	batchSize := 100
	numBatches := (len(accounts) + batchSize - 1) / batchSize

	for batch := 0; batch < numBatches; batch++ {
		start := batch * batchSize
		end := start + batchSize
		if end > len(accounts) {
			end = len(accounts)
		}

		nonceWg.Add(1)
		go func(batchStart, batchEnd int) {
			defer nonceWg.Done()
			for i := batchStart; i < batchEnd; i++ {
				addr := crypto.PubkeyToAddress(keys[i].PublicKey)
				nonce, err := clients[i%len(clients)].PendingNonceAt(ctx, addr)
				nonceMu.Lock()
				if err != nil {
					nonces[i] = 0
				} else {
					nonces[i] = nonce
				}
				nonceMu.Unlock()
			}
		}(start, end)

		if (batch+1)%10 == 0 {
			log.Printf("Fetching nonces: batch %d/%d", batch+1, numBatches)
		}
	}

	nonceWg.Wait()
	log.Printf("All %d accounts prepared with nonces", len(accounts))

	log.Println("Starting transaction sending...")

	var wg sync.WaitGroup
	var mu sync.Mutex

	totalTxs := 0
	successTxs := 0
	failedTxs := 0
	errorCounts := make(map[string]int)

	startTime := time.Now()
	endTime := startTime.Add(time.Duration(config.Duration) * time.Second)

	// Calculate how often to send batches
	// For 10 TPS, send 10 transactions every 1 second (1000ms)
	// For 1000 TPS, send 100 transactions every 100ms
	intervalMs := 100 // Send batch every 100ms
	txsPerBatch := (config.TargetTPS * intervalMs) / 1000
	if txsPerBatch < 1 {
		txsPerBatch = 1
	}

	log.Printf("Sending %d tx every %dms (target: %d TPS)", txsPerBatch, intervalMs, config.TargetTPS)

	// Use a semaphore to limit concurrent goroutines
	maxConcurrent := 1000
	sem := make(chan struct{}, maxConcurrent)

	ticker := time.NewTicker(time.Duration(intervalMs) * time.Millisecond)
	defer ticker.Stop()

	accountIndex := 0
	batchCount := 0

	for time.Now().Before(endTime) {
		select {
		case <-ticker.C:
			batchCount++

			for i := 0; i < txsPerBatch; i++ {
				idx := accountIndex % len(accounts)
				accountIndex++

				// Reserve nonce atomically before launching goroutine
				mu.Lock()
				nonce := nonces[idx]
				nonces[idx]++ // Increment immediately to reserve this nonce
				mu.Unlock()

				sem <- struct{}{} // Acquire semaphore
				wg.Add(1)
				go func(index int, txNonce uint64, clientIdx int) {
					defer wg.Done()
					defer func() { <-sem }() // Release semaphore

					// Random recipient
					recipientIdx := rand.Intn(len(accounts))
					recipient := common.HexToAddress(accounts[recipientIdx].Address)

					amount := big.NewInt(1)
					tx := types.NewTransaction(txNonce, recipient, amount, config.GasLimit, gasPrice, nil)
					signedTx, err := types.SignTx(tx, types.NewEIP155Signer(chainID), keys[index])
					if err != nil {
						mu.Lock()
						failedTxs++
						totalTxs++
						mu.Unlock()
						return
					}

					// Retry logic with exponential backoff
					maxRetries := 3
					var sendErr error
					for attempt := 0; attempt < maxRetries; attempt++ {
						// Use round-robin endpoint selection
						client := clients[clientIdx%len(clients)]
						sendErr = client.SendTransaction(ctx, signedTx)

						if sendErr == nil {
							// Success
							break
						}

						// Retry on network errors, but not on nonce/validation errors
						errStr := sendErr.Error()
						if attempt < maxRetries-1 {
							// Check if it's a retryable error (network/timeout)
							if containsAny(errStr, []string{"connection", "timeout", "EOF", "reset"}) {
								time.Sleep(time.Duration(50*(attempt+1)) * time.Millisecond)
								continue
							}
						}
						// Non-retryable error or max retries reached
						break
					}

					mu.Lock()
					totalTxs++
					if sendErr != nil {
						failedTxs++
						// Track error types
						errMsg := sendErr.Error()
						if len(errMsg) > 100 {
							errMsg = errMsg[:100]
						}
						errorCounts[errMsg]++
					} else {
						successTxs++
					}
					mu.Unlock()
				}(idx, nonce, i)
			}

			// Log progress every 10 seconds
			if batchCount%(10000/intervalMs) == 0 {
				elapsed := time.Since(startTime).Seconds()
				currentTPS := float64(successTxs) / elapsed
				log.Printf("Progress: %.0fs elapsed, sent: %d, success: %d, failed: %d, current TPS: %.2f",
					elapsed, totalTxs, successTxs, failedTxs, currentTPS)
			}
		}
	}

	log.Println("Waiting for remaining transactions to complete...")
	wg.Wait()

	elapsed := time.Since(startTime).Seconds()
	actualTPS := float64(successTxs) / elapsed

	log.Println("\n=== Test Results ===")
	log.Printf("Duration: %.2f seconds", elapsed)
	log.Printf("Total transactions: %d", totalTxs)
	log.Printf("Successful: %d", successTxs)
	log.Printf("Failed: %d", failedTxs)
	log.Printf("Actual TPS: %.2f", actualTPS)
	log.Printf("Target TPS: %d", config.TargetTPS)
	log.Printf("Achievement: %.2f%%", (actualTPS/float64(config.TargetTPS))*100)

	if len(errorCounts) > 0 {
		log.Println("\n=== Error Summary ===")
		for errMsg, count := range errorCounts {
			log.Printf("%d occurrences: %s", count, errMsg)
		}
	}
}
