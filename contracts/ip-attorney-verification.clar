;; IP Attorney Verification Contract
;; Validates intellectual property attorneys

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ATTORNEY_NOT_FOUND (err u101))
(define-constant ERR_ATTORNEY_EXISTS (err u102))

;; Data Variables
(define-data-var next-attorney-id uint u1)

;; Data Maps
(define-map attorneys
  { attorney-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    specialization: (string-ascii 100),
    bar-number: (string-ascii 50),
    status: (string-ascii 20),
    registration-date: uint,
    verified: bool
  }
)

(define-map attorney-by-principal
  { principal: principal }
  { attorney-id: uint }
)

;; Public Functions

;; Register a new attorney
(define-public (register-attorney (name (string-ascii 100)) (specialization (string-ascii 100)) (bar-number (string-ascii 50)))
  (let ((attorney-id (var-get next-attorney-id)))
    ;; Check if attorney already exists
    (asserts! (is-none (map-get? attorney-by-principal { principal: tx-sender })) ERR_ATTORNEY_EXISTS)

    (map-set attorneys
      { attorney-id: attorney-id }
      {
        principal: tx-sender,
        name: name,
        specialization: specialization,
        bar-number: bar-number,
        status: "pending",
        registration-date: block-height,
        verified: false
      }
    )

    (map-set attorney-by-principal
      { principal: tx-sender }
      { attorney-id: attorney-id }
    )

    (var-set next-attorney-id (+ attorney-id u1))
    (ok attorney-id)
  )
)

;; Verify an attorney (only contract owner)
(define-public (verify-attorney (attorney-id uint))
  (match (map-get? attorneys { attorney-id: attorney-id })
    attorney-data
    (begin
      (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
      (map-set attorneys
        { attorney-id: attorney-id }
        (merge attorney-data { verified: true, status: "verified" })
      )
      (ok true)
    )
    ERR_ATTORNEY_NOT_FOUND
  )
)

;; Update attorney status
(define-public (update-attorney-status (attorney-id uint) (new-status (string-ascii 20)))
  (match (map-get? attorneys { attorney-id: attorney-id })
    attorney-data
    (begin
      (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
      (map-set attorneys
        { attorney-id: attorney-id }
        (merge attorney-data { status: new-status })
      )
      (ok true)
    )
    ERR_ATTORNEY_NOT_FOUND
  )
)

;; Suspend attorney
(define-public (suspend-attorney (attorney-id uint))
  (match (map-get? attorneys { attorney-id: attorney-id })
    attorney-data
    (begin
      (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
      (map-set attorneys
        { attorney-id: attorney-id }
        (merge attorney-data { verified: false, status: "suspended" })
      )
      (ok true)
    )
    ERR_ATTORNEY_NOT_FOUND
  )
)

;; Read-only Functions

;; Get attorney information
(define-read-only (get-attorney (attorney-id uint))
  (map-get? attorneys { attorney-id: attorney-id })
)

;; Get attorney by principal
(define-read-only (get-attorney-by-principal (attorney-principal principal))
  (match (map-get? attorney-by-principal { principal: attorney-principal })
    attorney-ref
    (map-get? attorneys { attorney-id: (get attorney-id attorney-ref) })
    none
  )
)

;; Check if attorney is verified
(define-read-only (is-attorney-verified (attorney-id uint))
  (match (map-get? attorneys { attorney-id: attorney-id })
    attorney-data
    (get verified attorney-data)
    false
  )
)

;; Get total attorneys count
(define-read-only (get-total-attorneys)
  (- (var-get next-attorney-id) u1)
)

;; Check if attorney exists
(define-read-only (attorney-exists (attorney-id uint))
  (is-some (map-get? attorneys { attorney-id: attorney-id }))
)
