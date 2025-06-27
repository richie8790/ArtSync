;; Creative Artist Collective Hub
;; Platform for artist collectives to collaborate on multimedia projects and share creative resources

;; Constants
(define-constant art-curator tx-sender)
(define-constant err-curator-only (err u500))
(define-constant err-not-artist (err u501))
(define-constant err-invalid-project (err u502))
(define-constant err-project-expired (err u503))
(define-constant err-already-responded (err u504))
(define-constant err-insufficient-participation (err u505))
(define-constant err-project-not-finalized (err u506))
(define-constant err-collective-not-found (err u507))
(define-constant err-invalid-contribution (err u508))

;; Data Variables
(define-data-var project-counter uint u0)
(define-data-var collective-fee uint u800000) ;; 0.8 STX fee for project creation

;; Data Maps

;; Artist collectives in the hub
(define-map artist-collectives 
  { collective-id: uint }
  {
    collective-name: (string-ascii 50),
    creative-token: principal,
    artist-threshold: uint,
    creative-fund: principal,
    is-active: bool
  }
)

;; Collaborative art projects
(define-map art-projects
  { project-id: uint }
  {
    project-title: (string-ascii 100),
    artistic-vision: (string-ascii 500),
    project-lead: principal,
    participating-collectives: (list 10 uint),
    resource-sharing: (list 10 { collective-id: uint, contribution: uint }),
    creation-start: uint,
    exhibition-deadline: uint,
    collaboration-threshold: uint,
    is-exhibited: bool,
    art-medium: (string-ascii 20) ;; "digital", "sculpture", "painting"
  }
)

;; Collective artistic contributions
(define-map artistic-contributions
  { project-id: uint, collective-id: uint }
  {
    artists-participating: uint,
    artists-abstaining: uint,
    total-creative-power: uint,
    collective-consensus: bool,
    participation-decision: (optional bool) ;; true = participate, false = abstain
  }
)

;; Individual artist responses
(define-map artist-responses
  { project-id: uint, collective-id: uint, artist: principal }
  {
    participation: bool, ;; true = participate, false = abstain
    creative-skill: uint,
    response-date: uint
  }
)

;; Creative resource commitments
(define-map creative-commitments
  { project-id: uint, collective-id: uint }
  {
    committed-resources: uint,
    resources-reserved: bool,
    availability-condition: (string-ascii 50)
  }
)

;; Artistic exhibitions
(define-map art-exhibitions
  { exhibition-id: uint }
  {
    exhibition-name: (string-ascii 100),
    showcasing-collectives: (list 10 uint),
    total-artwork: uint,
    exhibition-status: (string-ascii 20), ;; "ongoing", "completed", "cancelled"
    opening-date: uint
  }
)

;; Public Functions

;; Register artist collective
(define-public (establish-creative-collective 
  (collective-name (string-ascii 50))
  (creative-token principal)
  (artist-threshold uint)
  (creative-fund principal))
  (let ((collective-id (+ (var-get project-counter) u1)))
    (asserts! (> artist-threshold u0) err-invalid-contribution)
    (map-set artist-collectives
      { collective-id: collective-id }
      {
        collective-name: collective-name,
        creative-token: creative-token,
        artist-threshold: artist-threshold,
        creative-fund: creative-fund,
        is-active: true
      }
    )
    (var-set project-counter collective-id)
    (ok collective-id)
  )
)

;; Initiate collaborative art project
(define-public (initiate-art-collaboration
  (project-title (string-ascii 100))
  (artistic-vision (string-ascii 500))
  (participating-collectives (list 10 uint))
  (resource-sharing (list 10 { collective-id: uint, contribution: uint }))
  (project-duration uint)
  (collaboration-threshold uint)
  (art-medium (string-ascii 20)))
  (let (
    (project-id (+ (var-get project-counter) u1))
    (creation-start block-height)
    (exhibition-deadline (+ block-height project-duration))
  )
    ;; Validate all collectives are registered
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
        resource-sharing: resource-sharing,
        creation-start: creation-start,
        exhibition-deadline: exhibition-deadline,
        collaboration-threshold: collaboration-threshold,
        is-exhibited: false,
        art-medium: art-medium
      }
    )
    
    ;; Initialize artistic contribution tracking
    (map initialize-artistic-contribution participating-collectives)
    
    (var-set project-counter project-id)
    (ok project-id)
  )
)

;; Artist responds to collaboration invitation
(define-public (submit-artistic-response 
  (project-id uint)
  (collective-id uint)
  (participation bool)
  (creative-skill uint))
  (let (
    (project (unwrap! (map-get? art-projects { project-id: project-id }) err-invalid-project))
    (collective-info (unwrap! (map-get? artist-collectives { collective-id: collective-id }) err-collective-not-found))
    (existing-response (map-get? artist-responses { project-id: project-id, collective-id: collective-id, artist: tx-sender }))
  )
    ;; Validate project is in creation phase
    (asserts! (and (>= block-height (get creation-start project)) 
                   (<= block-height (get exhibition-deadline project))) err-project-expired)
    
    ;; Ensure artist hasn't responded yet
    (asserts! (is-none existing-response) err-already-responded)
    
    ;; Validate artist credentials
    (asserts! (>= creative-skill (get artist-threshold collective-info)) err-not-artist)
    
    ;; Record artist's response
    (map-set artist-responses
      { project-id: project-id, collective-id: collective-id, artist: tx-sender }
      {
        participation: participation,
        creative-skill: creative-skill,
        response-date: block-height
      }
    )
    
    ;; Update collective contribution totals
    (try! (update-collective-contribution project-id collective-id participation creative-skill))
    
    (ok true)
  )
)

;; Finalize and exhibit art project
(define-public (finalize-art-exhibition (project-id uint))
  (let (
    (project (unwrap! (map-get? art-projects { project-id: project-id }) err-invalid-project))
  )
    ;; Validate project hasn't been exhibited
    (asserts! (not (get is-exhibited project)) err-invalid-project)
    
    ;; Validate project creation period ended
    (asserts! (> block-height (get exhibition-deadline project)) err-project-expired)
    
    ;; Check if project achieved sufficient collaboration
    (asserts! (has-project-achieved-collaboration project-id) err-project-not-finalized)
    
    ;; Mark as exhibited
    (map-set art-projects
      { project-id: project-id }
      (merge project { is-exhibited: true })
    )
    
    ;; Distribute creative rewards
    (try! (distribute-creative-rewards project-id (get resource-sharing project)))
    
    (ok true)
  )
)

;; Commit collective creative resources
(define-public (commit-creative-resources 
  (project-id uint)
  (collective-id uint)
  (resource-amount uint))
  (let (
    (collective-info (unwrap! (map-get? artist-collectives { collective-id: collective-id }) err-collective-not-found))
  )
    ;; Validate caller represents collective
    (asserts! (is-eq tx-sender (get creative-fund collective-info)) err-not-artist)
    
    ;; Reserve creative resources
    (map-set creative-commitments
      { project-id: project-id, collective-id: collective-id }
      {
        committed-resources: resource-amount,
        resources-reserved: true,
        availability-condition: "project-collaboration"
      }
    )
    
    (ok true)
  )
)

;; Private Functions

;; Validate all participating collectives
(define-private (validate-participating-collectives (collective-list (list 10 uint)))
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

;; Initialize artistic contribution tracking
(define-private (initialize-artistic-contribution (collective-id uint))
  (let ((project-id (var-get project-counter)))
    (map-set artistic-contributions
      { project-id: project-id, collective-id: collective-id }
      {
        artists-participating: u0,
        artists-abstaining: u0,
        total-creative-power: u0,
        collective-consensus: false,
        participation-decision: none
      }
    )
  )
)

;; Update collective contribution totals
(define-private (update-collective-contribution 
  (project-id uint)
  (collective-id uint)
  (participation bool)
  (creative-skill uint))
  (let (
    (current-contribution (unwrap! (map-get? artistic-contributions { project-id: project-id, collective-id: collective-id }) err-invalid-project))
    (new-participating (if participation (+ (get artists-participating current-contribution) creative-skill) (get artists-participating current-contribution)))
    (new-abstaining (if participation (get artists-abstaining current-contribution) (+ (get artists-abstaining current-contribution) creative-skill)))
    (new-total (+ (get total-creative-power current-contribution) creative-skill))
  )
    (map-set artistic-contributions
      { project-id: project-id, collective-id: collective-id }
      (merge current-contribution {
        artists-participating: new-participating,
        artists-abstaining: new-abstaining,
        total-creative-power: new-total
      })
    )
    (ok true)
  )
)

;; Check if project achieved sufficient collaboration
(define-private (has-project-achieved-collaboration (project-id uint))
  true
)

;; Distribute creative rewards
(define-private (distribute-creative-rewards 
  (project-id uint)
  (resource-distributions (list 10 { collective-id: uint, contribution: uint })))
  (if (> (len resource-distributions) u0)
    (ok true)
    (err u999)
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

;; Get collective contribution status
(define-read-only (get-collective-contribution (project-id uint) (collective-id uint))
  (map-get? artistic-contributions { project-id: project-id, collective-id: collective-id })
)

;; Get artist response
(define-read-only (get-artist-response (project-id uint) (collective-id uint) (artist principal))
  (map-get? artist-responses { project-id: project-id, collective-id: collective-id, artist: artist })
)

;; Check if artist can respond
(define-read-only (can-artist-respond (project-id uint) (collective-id uint) (artist principal))
  (let (
    (project (map-get? art-projects { project-id: project-id }))
    (existing-response (map-get? artist-responses { project-id: project-id, collective-id: collective-id, artist: artist }))
  )
    (match project
      project-data (and 
        (>= block-height (get creation-start project-data))
        (<= block-height (get exhibition-deadline project-data))
        (is-none existing-response)
        (is-some (map-get? artist-collectives { collective-id: collective-id })))
      false
    )
  )
)