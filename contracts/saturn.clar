;; Title: Saturn - Decentralized Content Curation Protocol
;;
;; Summary: A Bitcoin-anchored content curation and reputation system built on Stacks
;;
;; Description: 
;; Saturn is a decentralized content curation protocol that leverages Bitcoin's 
;; security through the Stacks blockchain. It enables community-driven content 
;; discovery with built-in economic incentives for quality contributions.
;; 
;; The protocol implements:
;; - Decentralized content submission with STX deposit requirements
;; - Community-powered content appraisal with reputation tracking
;; - Direct creator rewards through Bitcoin-backed micropayments
;; - Category-based content organization with administrative controls
;; - Protection against spam and low-quality content through economic design

;; Core Constants
(define-constant PROTOCOL_ADMINISTRATOR tx-sender)

;; Error Codes
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_INVALID_SUBMISSION (err u101))
(define-constant ERR_DUPLICATE_ENTRY (err u102))
(define-constant ERR_NONEXISTENT_ITEM (err u103))
(define-constant ERR_INADEQUATE_BALANCE (err u104))
(define-constant ERR_INVALID_TOPIC (err u105))
(define-constant ERR_INVALID_FLAG (err u106))
(define-constant ERR_OVERFLOW (err u107))
(define-constant ERR_INVALID_APPRAISAL (err u108))
(define-constant ERR_INVALID_ITEM_ID (err u109))

;; Protocol Parameters
(define-constant MIN_HYPERLINK_LENGTH u10)
(define-constant MAX_UINT u340282366920938463463374607431768211455)

;; State Variables
(define-data-var submission-charge uint u10)
(define-data-var aggregate-submissions uint u0)
(define-data-var content-topics (list 10 (string-ascii 20)) (list "Technology" "Science" "Art" "Politics" "Sports"))

;; Data Storage Maps
(define-map curated-items 
  { item-identifier: uint } 
  { 
    originator: principal, 
    headline: (string-ascii 100), 
    hyperlink: (string-ascii 200), 
    topic: (string-ascii 20),
    publication-epoch: uint, 
    appraisals: int,
    gratuities: uint,
    flags: uint
  }
)

(define-map participant-appraisals 
  { participant: principal, item-identifier: uint } 
  { appraisal: int }
)

(define-map participant-credibility
  { participant: principal }
  { metric: int }
)

;; Private Helper Functions

;; Check if an item exists in the curation database
(define-private (item-exists (item-identifier uint))
  (is-some (map-get? curated-items { item-identifier: item-identifier }))
)

;; Filter valid items for top content retrieval
(define-private (not-none (item (optional {
    originator: principal, 
    headline: (string-ascii 100), 
    hyperlink: (string-ascii 200), 
    topic: (string-ascii 20),
    publication-epoch: uint, 
    appraisals: int,
    gratuities: uint,
    flags: uint
  })))
  (is-some item)
)

;; Retrieve item if it meets quality threshold (non-negative appraisals)
(define-private (retrieve-item-if-valid (id uint))
  (match (map-get? curated-items { item-identifier: id })
    item (if (>= (get appraisals item) 0) (some item) none)
    none
  )
)

;; Generate a bounded list of sequential numbers
(define-private (enumerate (n uint))
  (let ((limit (if (> n u10) u10 n)))
    (list
      (if (>= limit u1) u1 u0)
      (if (>= limit u2) u2 u0)
      (if (>= limit u3) u3 u0)
      (if (>= limit u4) u4 u0)
      (if (>= limit u5) u5 u0)
      (if (>= limit u6) u6 u0)
      (if (>= limit u7) u7 u0)
      (if (>= limit u8) u8 u0)
      (if (>= limit u9) u9 u0)
      (if (>= limit u10) u10 u0)
    )
  )
)

;; Filter non-zero values from a list
(define-private (is-non-zero (n uint))
  (not (is-eq n u0))
)

;; Public Content Curation Functions

;; Submit new content for community curation
(define-public (contribute-item (headline (string-ascii 100)) (hyperlink (string-ascii 200)) (topic (string-ascii 20)))
  (let
    (
      (item-identifier (+ (var-get aggregate-submissions) u1))
    )
    (asserts! (and 
                (>= (len headline) u1)
                (>= (len hyperlink) MIN_HYPERLINK_LENGTH)
                (>= (len topic) u1)
              ) ERR_INVALID_SUBMISSION)
    (asserts! (> item-identifier (var-get aggregate-submissions)) ERR_OVERFLOW)
    (asserts! (is-some (index-of (var-get content-topics) topic)) ERR_INVALID_TOPIC)
    (asserts! (>= (stx-get-balance tx-sender) (var-get submission-charge)) ERR_INADEQUATE_BALANCE)
    (try! (stx-transfer? (var-get submission-charge) tx-sender PROTOCOL_ADMINISTRATOR))
    (map-set curated-items
      { item-identifier: item-identifier }
      {
        originator: tx-sender,
        headline: headline,
        hyperlink: hyperlink,
        topic: topic,
        publication-epoch: stacks-block-height,
        appraisals: 0,
        gratuities: u0,
        flags: u0
      }
    )
    (var-set aggregate-submissions item-identifier)
    (print { type: "new-item", item-identifier: item-identifier, originator: tx-sender })
    (ok item-identifier)
  )
)

;; Vote on curated content with reputation implications
(define-public (appraise-item (item-identifier uint) (appraisal int))
  (let
    (
      (previous-appraisal (default-to 0 (get appraisal (map-get? participant-appraisals { participant: tx-sender, item-identifier: item-identifier }))))
      (target-item (unwrap! (map-get? curated-items { item-identifier: item-identifier }) ERR_NONEXISTENT_ITEM))
      (appraiser-standing (default-to { metric: 0 } (map-get? participant-credibility { participant: tx-sender })))
    )
    (asserts! (item-exists item-identifier) ERR_NONEXISTENT_ITEM)
    (asserts! (or (is-eq appraisal 1) (is-eq appraisal -1)) ERR_INVALID_APPRAISAL)
    (map-set participant-appraisals
      { participant: tx-sender, item-identifier: item-identifier }
      { appraisal: appraisal }
    )
    (map-set curated-items
      { item-identifier: item-identifier }
      (merge target-item { appraisals: (+ (get appraisals target-item) (- appraisal previous-appraisal)) })
    )
    (map-set participant-credibility
      { participant: tx-sender }
      { metric: (+ (get metric appraiser-standing) appraisal) }
    )
    (print { type: "appraisal", item-identifier: item-identifier, appraiser: tx-sender, appraisal: appraisal })
    (ok true)
  )
)