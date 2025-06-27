;; Creative Artist Collective Hub - Stage 1
;; Basic platform for artist collective registration and simple project creation

;; Constants
(define-constant art-curator tx-sender)
(define-constant err-curator-only (err u500))
(define-constant err-not-artist (err u501))
(define-constant err-invalid-project (err u502))
(define-constant err-collective-not-found (err u507))
(define-constant err-invalid-contribution (err u508))

;; Data Variables
(define-data-var project-counter uint u0)
(define-data-var collective-fee uint u500000) ;; 0.5 STX fee for project creation

;; Data Maps

;; Artist collectives in the hub
(define-map artist-collectives 
  { collective-id: uint }
  {
    collective-name: (string-ascii 50),
    creative-token: principal,
    artist-threshold: uint,
    is-active: bool
  }
)

;; Basic art projects
(define-map art-projects
  { project-id: uint }
  {
    project-title: (string-ascii 100),
    artistic-vision: (string-ascii 300),
    project-lead: principal,
    participating-collectives: (list 5 uint),
    creation-start: uint,
    project-duration: uint,
    is-active: bool
  }
)

;; Simple artist participation tracking
(define-map artist-participation
  { project-id: uint, artist: principal }
  {
    participation: bool,
    join-date: uint
  }
)

;; Public Functions

;; Register artist collective
(define-public (establish-creative-collective 
  (collective-name (string-ascii 50))
  (creative-token principal)
  (artist-threshold uint))
  (let ((collective-id (+ (var-get project-counter) u1)))
    (asserts! (> artist-threshold u0) err-invalid-contribution)
    (map-set artist-collectives
      { collective-id: collective-id }
      {
        collective-name: collective-name,
        creative-token: creative-token,
        artist-threshold: artist-threshold,
        is-active: true
      }
    )
    (var-set project-counter collective-id)
    (ok collective-id)
  )
)

;; Create basic art project
(define-public (create-art-project
  (project-title (string-ascii 100))
  (artistic-vision (string-ascii 300))
  (participating-collectives (list 5 uint))
  (project-duration uint))
  (let (
    (project-id (+ (var-get project-counter) u1))
    (creation-start block-height)
  )
    ;; Validate all collectives exist
    (asserts! (is-ok (validate-participating-collectives participating-collectives)) err-collective-not-found)
    
    ;; Pay collective fee
    (try! (stx-transfer? (var-get collective-fee) tx-sender art-curator))
    
    ;; Create art project
    (map-set art-projects
      { project-id: project-id }
      {
        project-title: project-title,
        artistic-vision: artistic-vision,
        project-lead: tx-sender,
        participating-collectives: participating-collectives,
        creation-start: creation-start,
        project-duration: project-duration,
        is-active: true
      }
    )
    
    (var-set project-counter project-id)
    (ok project-id)
  )
)

;; Join art project as artist
(define-public (join-art-project (project-id uint))
  (let (
    (project (unwrap! (map-get? art-projects { project-id: project-id }) err-invalid-project))
    (existing-participation (map-get? artist-participation { project-id: project-id, artist: tx-sender }))
  )
    ;; Validate project is active
    (asserts! (get is-active project) err-invalid-project)
    
    ;; Ensure artist hasn't joined yet
    (asserts! (is-none existing-participation) err-not-artist)
    
    ;; Record artist's participation
    (map-set artist-participation
      { project-id: project-id, artist: tx-sender }
      {
        participation: true,
        join-date: block-height
      }
    )
    
    (ok true)
  )
)

;; Deactivate project
(define-public (deactivate-project (project-id uint))
  (let (
    (project (unwrap! (map-get? art-projects { project-id: project-id }) err-invalid-project))
  )
    ;; Only project lead can deactivate
    (asserts! (is-eq tx-sender (get project-lead project)) err-curator-only)
    
    ;; Deactivate project
    (map-set art-projects
      { project-id: project-id }
      (merge project { is-active: false })
    )
    
    (ok true)
  )
)

;; Private Functions

;; Validate all participating collectives
(define-private (validate-participating-collectives (collective-list (list 5 uint)))
  (fold check-collective-exists collective-list (ok true))
)

(define-private (check-collective-exists (collective-id uint) (previous-result (response bool uint)))
  (match previous-result
    success (if (is-some (map-get? artist-collectives { collective-id: collective-id }))
              (ok true)
              err-collective-not-found)
    error (err error)
  )
)

;; Read-only Functions

;; Get project details
(define-read-only (get-project-details (project-id uint))
  (map-get? art-projects { project-id: project-id })
)

;; Get collective information
(define-read-only (get-collective-info (collective-id uint))
  (map-get? artist-collectives { collective-id: collective-id })
)

;; Get artist participation
(define-read-only (get-artist-participation (project-id uint) (artist principal))
  (map-get? artist-participation { project-id: project-id, artist: artist })
)

;; Check if project is active
(define-read-only (is-project-active (project-id uint))
  (match (map-get? art-projects { project-id: project-id })
    project-data (get is-active project-data)
    false
  )
)

;; Get total project count
(define-read-only (get-project-count)
  (var-get project-counter)
)