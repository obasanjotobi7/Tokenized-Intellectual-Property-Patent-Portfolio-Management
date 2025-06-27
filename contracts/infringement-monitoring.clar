;; Infringement Monitoring Contract
;; Monitors patent infringement cases and enforcement

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CASE_NOT_FOUND (err u108))
(define-constant ERR_INVALID_EVIDENCE (err u109))

;; Data Variables
(define-data-var next-case-id uint u1)

;; Data Maps
(define-map infringement-cases
  { case-id: uint }
  {
    patent-id: uint,
    reporter: principal,
    alleged-infringer: principal,
    description: (string-ascii 500),
    severity: (string-ascii 20),
    status: (string-ascii 30),
    report-date: uint,
    resolution-date: (optional uint),
    damages-claimed: uint
  }
)

(define-map case-evidence
  { case-id: uint, evidence-id: uint }
  {
    evidence-type: (string-ascii 50),
    description: (string-ascii 300),
    submitted-by: principal,
    submission-date: uint,
    verified: bool
  }
)

(define-map enforcement-actions
  { case-id: uint }
  {
    action-type: (string-ascii 50),
    initiated-by: principal,
    target: principal,
    action-date: uint,
    status: (string-ascii 30),
    outcome: (optional (string-ascii 200))
  }
)

(define-map case-settlements
  { case-id: uint }
  {
    settlement-amount: uint,
    settlement-date: uint,
    terms: (string-ascii 300),
    agreed-by-infringer: bool,
    agreed-by-patent-holder: bool
  }
)

;; Public Functions

;; Report patent infringement
(define-public (report-infringement (patent-id uint) (alleged-infringer principal) (description (string-ascii 500)) (severity (string-ascii 20)) (damages-claimed uint))
  (let ((case-id (var-get next-case-id)))
    ;; Simple patent validation (in production, this would verify actual ownership)
    (begin
      (asserts! (> patent-id u0) ERR_UNAUTHORIZED)

      (map-set infringement-cases
        { case-id: case-id }
        {
          patent-id: patent-id,
          reporter: tx-sender,
          alleged-infringer: alleged-infringer,
          description: description,
          severity: severity,
          status: "reported",
          report-date: block-height,
          resolution-date: none,
          damages-claimed: damages-claimed
        }
      )

      (var-set next-case-id (+ case-id u1))
      (ok case-id)
    )
  )
)

;; Submit evidence for a case
(define-public (submit-evidence (case-id uint) (evidence-type (string-ascii 50)) (description (string-ascii 300)))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (let ((evidence-id block-height))
      (asserts!
        (or
          (is-eq tx-sender (get reporter case-data))
          (is-eq tx-sender (get alleged-infringer case-data))
        )
        ERR_UNAUTHORIZED
      )

      (map-set case-evidence
        { case-id: case-id, evidence-id: evidence-id }
        {
          evidence-type: evidence-type,
          description: description,
          submitted-by: tx-sender,
          submission-date: block-height,
          verified: false
        }
      )

      (ok evidence-id)
    )
    ERR_CASE_NOT_FOUND
  )
)

;; Verify evidence (only contract owner or authorized parties)
(define-public (verify-evidence (case-id uint) (evidence-id uint))
  (match (map-get? case-evidence { case-id: case-id, evidence-id: evidence-id })
    evidence-data
    (begin
      (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
      (map-set case-evidence
        { case-id: case-id, evidence-id: evidence-id }
        (merge evidence-data { verified: true })
      )
      (ok true)
    )
    ERR_INVALID_EVIDENCE
  )
)

;; Initiate enforcement action
(define-public (initiate-enforcement (case-id uint) (action-type (string-ascii 50)) (target principal))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (begin
      (asserts! (is-eq tx-sender (get reporter case-data)) ERR_UNAUTHORIZED)

      (map-set enforcement-actions
        { case-id: case-id }
        {
          action-type: action-type,
          initiated-by: tx-sender,
          target: target,
          action-date: block-height,
          status: "initiated",
          outcome: none
        }
      )

      ;; Update case status
      (map-set infringement-cases
        { case-id: case-id }
        (merge case-data { status: "enforcement-initiated" })
      )

      (ok true)
    )
    ERR_CASE_NOT_FOUND
  )
)

;; Propose settlement
(define-public (propose-settlement (case-id uint) (settlement-amount uint) (terms (string-ascii 300)))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (begin
      (asserts!
        (or
          (is-eq tx-sender (get reporter case-data))
          (is-eq tx-sender (get alleged-infringer case-data))
        )
        ERR_UNAUTHORIZED
      )

      (map-set case-settlements
        { case-id: case-id }
        {
          settlement-amount: settlement-amount,
          settlement-date: block-height,
          terms: terms,
          agreed-by-infringer: (is-eq tx-sender (get alleged-infringer case-data)),
          agreed-by-patent-holder: (is-eq tx-sender (get reporter case-data))
        }
      )

      (ok true)
    )
    ERR_CASE_NOT_FOUND
  )
)

;; Accept settlement
(define-public (accept-settlement (case-id uint))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (match (map-get? case-settlements { case-id: case-id })
      settlement-data
      (begin
        (asserts!
          (or
            (is-eq tx-sender (get reporter case-data))
            (is-eq tx-sender (get alleged-infringer case-data))
          )
          ERR_UNAUTHORIZED
        )

        (let ((updated-settlement
          (if (is-eq tx-sender (get alleged-infringer case-data))
            (merge settlement-data { agreed-by-infringer: true })
            (merge settlement-data { agreed-by-patent-holder: true })
          )))

          (map-set case-settlements { case-id: case-id } updated-settlement)

          ;; If both parties agreed, execute settlement
          (if (and (get agreed-by-infringer updated-settlement) (get agreed-by-patent-holder updated-settlement))
            (begin
              (try! (stx-transfer? (get settlement-amount settlement-data) (get alleged-infringer case-data) (get reporter case-data)))
              (map-set infringement-cases
                { case-id: case-id }
                (merge case-data { status: "settled", resolution-date: (some block-height) })
              )
            )
            true
          )
        )

        (ok true)
      )
      ERR_CASE_NOT_FOUND
    )
    ERR_CASE_NOT_FOUND
  )
)

;; Update case status
(define-public (update-case-status (case-id uint) (new-status (string-ascii 30)))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (begin
      (asserts!
        (or
          (is-eq tx-sender CONTRACT_OWNER)
          (is-eq tx-sender (get reporter case-data))
        )
        ERR_UNAUTHORIZED
      )
      (map-set infringement-cases
        { case-id: case-id }
        (merge case-data { status: new-status })
      )
      (ok true)
    )
    ERR_CASE_NOT_FOUND
  )
)

;; Read-only Functions

;; Get infringement case
(define-read-only (get-infringement-case (case-id uint))
  (map-get? infringement-cases { case-id: case-id })
)

;; Get case evidence
(define-read-only (get-case-evidence (case-id uint) (evidence-id uint))
  (map-get? case-evidence { case-id: case-id, evidence-id: evidence-id })
)

;; Get enforcement action
(define-read-only (get-enforcement-action (case-id uint))
  (map-get? enforcement-actions { case-id: case-id })
)

;; Get case settlement
(define-read-only (get-case-settlement (case-id uint))
  (map-get? case-settlements { case-id: case-id })
)

;; Check if case is resolved
(define-read-only (is-case-resolved (case-id uint))
  (match (map-get? infringement-cases { case-id: case-id })
    case-data
    (or
      (is-eq (get status case-data) "settled")
      (is-eq (get status case-data) "dismissed")
      (is-eq (get status case-data) "resolved")
    )
    false
  )
)

;; Get total cases count
(define-read-only (get-total-cases)
  (- (var-get next-case-id) u1)
)

