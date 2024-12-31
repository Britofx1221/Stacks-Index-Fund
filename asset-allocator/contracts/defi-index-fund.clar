;; Multi-Token Index Fund Smart Contract

;; Define SIP-010 Fungible Token trait
(define-trait sip-010-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; The human readable name of the token
    (get-name () (response (string-ascii 32) uint))

    ;; The ticker symbol, or empty if none
    (get-symbol () (response (string-ascii 32) uint))

    ;; The number of decimals used, e.g. 6 would mean 1_000_000 represents 1 token
    (get-decimals () (response uint uint))

    ;; The balance of the passed principal
    (get-balance (principal) (response uint uint))

    ;; The current total supply (which does not need to be a constant)
    (get-total-supply () (response uint uint))

    ;; Optional URI for off-chain metadata
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Token contract references - using shorter principal format
(define-constant base-token-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.my-token)

;; Error codes
(define-constant ERROR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERROR-INVALID-DEPOSIT-AMOUNT (err u101))
(define-constant ERROR-INSUFFICIENT-USER-BALANCE (err u102))
(define-constant ERROR-UNSUPPORTED-TOKEN-TYPE (err u103))
(define-constant ERROR-REBALANCE-THRESHOLD-NOT-MET (err u104))
(define-constant ERROR-REBALANCE-OPERATION-FAILED (err u105))
(define-constant ERROR-INVALID-TOKEN-IDENTIFIER (err u106))
(define-constant ERROR-INVALID-ALLOCATION-PERCENTAGE (err u107))
(define-constant ERROR-INVALID-TOKEN-PRICE (err u108))
(define-constant ERROR-INVALID-TOKEN-CONTRACT-ADDRESS (err u109))

;; Constants
(define-constant INDEX-FUND-ADMINISTRATOR tx-sender)
(define-constant ANNUAL-MANAGEMENT-FEE-BASIS-POINTS u30) ;; 0.3% annual management fee
(define-constant PORTFOLIO-REBALANCE-THRESHOLD-BASIS-POINTS u500) ;; 5% deviation threshold
(define-constant MAXIMUM_TOKEN_COUNT u10) ;; Maximum number of tokens in the index

;; Data vars
(define-data-var last-rebalance-block-height uint u0)
(define-data-var total-fund-supply uint u0)
(define-data-var is-contract-paused bool false)
(define-data-var supported-token-identifiers (list 10 (string-ascii 32)) (list))

;; Data maps
(define-map investor-token-balances principal uint)
(define-map token-target-weights (string-ascii 32) uint)
(define-map token-support-status (string-ascii 32) bool)
(define-map token-current-prices (string-ascii 32) uint)
(define-map token-contract-addresses (string-ascii 32) principal)

;; Private functions
(define-private (absolute-difference (number int))
    (if (< number 0)
        (* number -1)
        number))

(define-private (is-administrator)
    (is-eq tx-sender INDEX-FUND-ADMINISTRATOR))

(define-private (calculate-period-management-fee (withdrawal-amount uint))
    (let ((blocks-since-last-rebalance (- block-height (var-get last-rebalance-block-height))))
        (/ (* withdrawal-amount ANNUAL-MANAGEMENT-FEE-BASIS-POINTS blocks-since-last-rebalance) 
           (* u10000 u52560))))

(define-private (get-token-weight-target (token-identifier (string-ascii 32)))
    (default-to u0 (map-get? token-target-weights token-identifier)))

(define-private (is-token-in-index (token-identifier (string-ascii 32)))
    (default-to false (map-get? token-support-status token-identifier)))

(define-private (get-token-contract-address (token-identifier (string-ascii 32)))
    (default-to base-token-contract (map-get? token-contract-addresses token-identifier)))

;; Public functions
(define-public (add-token-to-index 
    (token-identifier (string-ascii 32)) 
    (weight-percentage uint)
    (token-contract-id <sip-010-trait>))
    (begin
        (asserts! (is-administrator) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (< (len (var-get supported-token-identifiers)) MAXIMUM_TOKEN_COUNT) ERROR-UNSUPPORTED-TOKEN-TYPE)
        (asserts! (is-none (map-get? token-support-status token-identifier)) ERROR-INVALID-TOKEN-IDENTIFIER)
        (asserts! (> weight-percentage u0) ERROR-INVALID-ALLOCATION-PERCENTAGE)
        (asserts! (not (is-eq (contract-of token-contract-id) (as-contract tx-sender))) ERROR-INVALID-TOKEN-CONTRACT-ADDRESS)
        (map-set token-support-status token-identifier true)
        (map-set token-target-weights token-identifier weight-percentage)
        (map-set token-contract-addresses token-identifier (contract-of token-contract-id))
        (var-set supported-token-identifiers (unwrap! (as-max-len? (append (var-get supported-token-identifiers) token-identifier) u10) ERROR-UNSUPPORTED-TOKEN-TYPE))
        (ok true)))

(define-public (deposit-tokens (token-identifier (string-ascii 32)) (token-contract-instance <sip-010-trait>) (deposit-amount uint))
    (begin
        (asserts! (not (var-get is-contract-paused)) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (> deposit-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (is-token-in-index token-identifier) ERROR-UNSUPPORTED-TOKEN-TYPE)
        (asserts! (is-eq (contract-of token-contract-instance) (get-token-contract-address token-identifier)) ERROR-UNSUPPORTED-TOKEN-TYPE)
        
        ;; Transfer tokens to contract
        (try! (contract-call? token-contract-instance transfer 
            deposit-amount 
            tx-sender 
            (as-contract tx-sender)
            none))
        
        ;; Update investor balance
        (let ((current-investor-balance (default-to u0 (map-get? investor-token-balances tx-sender))))
            (map-set investor-token-balances tx-sender (+ current-investor-balance deposit-amount)))
        
        (var-set total-fund-supply (+ (var-get total-fund-supply) deposit-amount))
        (ok true)))

(define-public (withdraw-tokens (token-identifier (string-ascii 32)) (token-contract-instance <sip-010-trait>) (withdrawal-amount uint))
    (begin
        (asserts! (not (var-get is-contract-paused)) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (> withdrawal-amount u0) ERROR-INVALID-DEPOSIT-AMOUNT)
        (asserts! (is-token-in-index token-identifier) ERROR-UNSUPPORTED-TOKEN-TYPE)
        (asserts! (is-eq (contract-of token-contract-instance) (get-token-contract-address token-identifier)) ERROR-UNSUPPORTED-TOKEN-TYPE)
        
        (let ((current-investor-balance (default-to u0 (map-get? investor-token-balances tx-sender))))
            (asserts! (>= current-investor-balance withdrawal-amount) ERROR-INSUFFICIENT-USER-BALANCE)
            
            ;; Calculate and deduct management fee
            (let ((management-fee (calculate-period-management-fee withdrawal-amount))
                  (net-withdrawal-amount (- withdrawal-amount management-fee)))
                
                ;; Transfer tokens to investor
                (try! (as-contract (contract-call? token-contract-instance transfer 
                    net-withdrawal-amount 
                    (as-contract tx-sender) 
                    tx-sender
                    none)))
                
                ;; Update balances
                (map-set investor-token-balances tx-sender (- current-investor-balance withdrawal-amount))
                (var-set total-fund-supply (- (var-get total-fund-supply) withdrawal-amount))
                (ok true)))))

(define-public (rebalance-portfolio)
    (begin
        (asserts! (not (var-get is-contract-paused)) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (is-administrator) ERROR-UNAUTHORIZED-ACCESS)
        
        ;; Check if rebalancing is needed
        (let ((total-deviation-percentage (calculate-total-portfolio-deviation)))
            (if (> total-deviation-percentage PORTFOLIO-REBALANCE-THRESHOLD-BASIS-POINTS)
                (begin
                    (var-set last-rebalance-block-height block-height)
                    (execute-portfolio-rebalance))
                ERROR-REBALANCE-THRESHOLD-NOT-MET))))

(define-private (calculate-total-portfolio-deviation)
    (let ((index-tokens (var-get supported-token-identifiers)))
        (fold + 
            (map calculate-token-weight-deviation index-tokens)
            u0)))

(define-private (calculate-token-weight-deviation (token-identifier (string-ascii 32)))
    (let ((target-weight (get-token-weight-target token-identifier))
          (current-weight (calculate-current-token-weight token-identifier)))
        (to-uint (absolute-difference (- (to-int target-weight) (to-int current-weight))))))

(define-private (calculate-current-token-weight (token-identifier (string-ascii 32)))
    (let ((token-price (default-to u0 (map-get? token-current-prices token-identifier)))
          (token-balance (default-to u0 (map-get? investor-token-balances tx-sender))))
        (/ (* token-balance token-price) (var-get total-fund-supply))))

(define-private (execute-portfolio-rebalance)
    (begin
        (ok true)))

;; Read-only functions
(define-read-only (get-investor-balance (investor-address principal))
    (default-to u0 (map-get? investor-token-balances investor-address)))

(define-read-only (get-token-weight (token-identifier (string-ascii 32)))
    (get-token-weight-target token-identifier))

(define-read-only (get-index-tokens)
    (var-get supported-token-identifiers))

(define-read-only (get-total-fund-supply)
    (var-get total-fund-supply))

;; Admin functions
(define-public (update-token-price (token-identifier (string-ascii 32)) (current-price uint))
    (begin
        (asserts! (is-administrator) ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (is-token-in-index token-identifier) ERROR-UNSUPPORTED-TOKEN-TYPE)
        (asserts! (> current-price u0) ERROR-INVALID-TOKEN-PRICE)
        (map-set token-current-prices token-identifier current-price)
        (ok true)))

(define-public (pause-contract)
    (begin
        (asserts! (is-administrator) ERROR-UNAUTHORIZED-ACCESS)
        (var-set is-contract-paused true)
        (ok true)))

(define-public (resume-contract)
    (begin
        (asserts! (is-administrator) ERROR-UNAUTHORIZED-ACCESS)
        (var-set is-contract-paused false)
        (ok true)))