;; Maintenance Scheduling Contract
;; Coordinates cleaning and tuning procedures

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_CHIME_NOT_FOUND (err u401))
(define-constant ERR_INVALID_SCHEDULE (err u402))
(define-constant ERR_MAINTENANCE_NOT_FOUND (err u403))
(define-constant ERR_VOLUNTEER_NOT_AVAILABLE (err u404))

;; Data Variables
(define-data-var maintenance-reward-amount uint u100) ;; Reward for completing maintenance
(define-data-var max-maintenance-interval uint u4320) ;; Maximum blocks between maintenance (approx 30 days)

;; Data Maps
(define-map chime-maintenance-schedule
  { chime-id: uint }
  {
    last-maintenance: uint,
    next-scheduled: uint,
    maintenance-interval: uint, ;; Blocks between maintenance
    maintenance-type-needed: (string-ascii 50),
    priority-level: uint, ;; 1-5 scale (5 = urgent)
    assigned-volunteer: (optional principal),
    maintenance-notes: (string-ascii 200)
  }
)

(define-map maintenance-tasks
  { task-id: uint }
  {
    chime-id: uint,
    task-type: (string-ascii 50), ;; "cleaning", "tuning", "repair", "inspection"
    description: (string-ascii 200),
    estimated-duration: uint, ;; In blocks
    required-skills: (string-ascii 100),
    assigned-to: (optional principal),
    created-by: principal,
    creation-block: uint,
    status: (string-ascii 20), ;; "pending", "assigned", "in-progress", "completed", "cancelled"
    completion-block: (optional uint)
  }
)

(define-map volunteer-profiles
  { volunteer: principal }
  {
    skills: (string-ascii 200),
    availability-schedule: (string-ascii 100),
    completed-tasks: uint,
    reliability-score: uint, ;; 0-100 scale
    preferred-task-types: (string-ascii 100),
    contact-info: (string-ascii 100),
    active: bool
  }
)

(define-map maintenance-history
  { chime-id: uint, history-id: uint }
  {
    maintenance-date: uint,
    maintenance-type: (string-ascii 50),
    performed-by: principal,
    duration: uint,
    issues-found: (string-ascii 200),
    actions-taken: (string-ascii 200),
    next-maintenance-recommendation: uint,
    quality-rating: uint ;; 0-10 scale
  }
)

(define-map maintenance-supplies
  { supply-id: uint }
  {
    supply-name: (string-ascii 50),
    quantity-available: uint,
    unit-cost: uint,
    supplier: (string-ascii 100),
    last-restocked: uint,
    minimum-threshold: uint
  }
)

;; Data Lists
(define-data-var next-task-id uint u1)
(define-data-var next-history-id uint u1)
(define-data-var next-supply-id uint u1)

;; Public Functions

;; Schedule maintenance for a chime
(define-public (schedule-maintenance (chime-id uint) (maintenance-type (string-ascii 50)) (priority-level uint) (maintenance-interval uint))
  (begin
    (asserts! (<= priority-level u5) ERR_INVALID_SCHEDULE)
    (asserts! (> maintenance-interval u0) ERR_INVALID_SCHEDULE)
    (map-set chime-maintenance-schedule
      { chime-id: chime-id }
      {
        last-maintenance: block-height,
        next-scheduled: (+ block-height maintenance-interval),
        maintenance-interval: maintenance-interval,
        maintenance-type-needed: maintenance-type,
        priority-level: priority-level,
        assigned-volunteer: none,
        maintenance-notes: ""
      }
    )
    (print { event: "maintenance-scheduled", chime-id: chime-id, type: maintenance-type, priority: priority-level })
    (ok true)
  )
)

;; Create maintenance task
(define-public (create-maintenance-task (chime-id uint) (task-type (string-ascii 50)) (description (string-ascii 200)) (estimated-duration uint) (required-skills (string-ascii 100)))
  (let ((task-id (var-get next-task-id)))
    (map-set maintenance-tasks
      { task-id: task-id }
      {
        chime-id: chime-id,
        task-type: task-type,
        description: description,
        estimated-duration: estimated-duration,
        required-skills: required-skills,
        assigned-to: none,
        created-by: tx-sender,
        creation-block: block-height,
        status: "pending",
        completion-block: none
      }
    )
    (var-set next-task-id (+ task-id u1))
    (print { event: "task-created", task-id: task-id, chime-id: chime-id, type: task-type })
    (ok task-id)
  )
)

;; Register as volunteer
(define-public (register-volunteer (skills (string-ascii 200)) (availability (string-ascii 100)) (preferred-tasks (string-ascii 100)) (contact-info (string-ascii 100)))
  (begin
    (map-set volunteer-profiles
      { volunteer: tx-sender }
      {
        skills: skills,
        availability-schedule: availability,
        completed-tasks: u0,
        reliability-score: u100, ;; Start with perfect score
        preferred-task-types: preferred-tasks,
        contact-info: contact-info,
        active: true
      }
    )
    (print { event: "volunteer-registered", volunteer: tx-sender })
    (ok true)
  )
)

;; Assign task to volunteer
(define-public (assign-task (task-id uint) (volunteer principal))
  (match (map-get? maintenance-tasks { task-id: task-id })
    task-data
      (match (map-get? volunteer-profiles { volunteer: volunteer })
        volunteer-data
          (if (get active volunteer-data)
            (begin
              (map-set maintenance-tasks
                { task-id: task-id }
                (merge task-data { assigned-to: (some volunteer), status: "assigned" })
              )
              (print { event: "task-assigned", task-id: task-id, volunteer: volunteer })
              (ok true)
            )
            ERR_VOLUNTEER_NOT_AVAILABLE
          )
        ERR_VOLUNTEER_NOT_AVAILABLE
      )
    ERR_MAINTENANCE_NOT_FOUND
  )
)

;; Start maintenance task
(define-public (start-task (task-id uint))
  (match (map-get? maintenance-tasks { task-id: task-id })
    task-data
      (if (is-eq (some tx-sender) (get assigned-to task-data))
        (begin
          (map-set maintenance-tasks
            { task-id: task-id }
            (merge task-data { status: "in-progress" })
          )
          (print { event: "task-started", task-id: task-id, volunteer: tx-sender })
          (ok true)
        )
        ERR_UNAUTHORIZED
      )
    ERR_MAINTENANCE_NOT_FOUND
  )
)

;; Complete maintenance task
(define-public (complete-task (task-id uint) (issues-found (string-ascii 200)) (actions-taken (string-ascii 200)) (quality-rating uint))
  (match (map-get? maintenance-tasks { task-id: task-id })
    task-data
      (if (is-eq (some tx-sender) (get assigned-to task-data))
        (let ((history-id (var-get next-history-id))
              (chime-id (get chime-id task-data)))
          (asserts! (<= quality-rating u10) ERR_INVALID_SCHEDULE)
          ;; Complete the task
          (map-set maintenance-tasks
            { task-id: task-id }
            (merge task-data { status: "completed", completion-block: (some block-height) })
          )
          ;; Record maintenance history
          (map-set maintenance-history
            { chime-id: chime-id, history-id: history-id }
            {
              maintenance-date: block-height,
              maintenance-type: (get task-type task-data),
              performed-by: tx-sender,
              duration: (get estimated-duration task-data),
              issues-found: issues-found,
              actions-taken: actions-taken,
              next-maintenance-recommendation: (+ block-height (var-get max-maintenance-interval)),
              quality-rating: quality-rating
            }
          )
          (var-set next-history-id (+ history-id u1))
          ;; Update volunteer profile
          (match (map-get? volunteer-profiles { volunteer: tx-sender })
            volunteer-data
              (map-set volunteer-profiles
                { volunteer: tx-sender }
                (merge volunteer-data { completed-tasks: (+ (get completed-tasks volunteer-data) u1) })
              )
            false
          )
          ;; Update chime maintenance schedule
          (match (map-get? chime-maintenance-schedule { chime-id: chime-id })
            schedule-data
              (map-set chime-maintenance-schedule
                { chime-id: chime-id }
                (merge schedule-data {
                  last-maintenance: block-height,
                  next-scheduled: (+ block-height (get maintenance-interval schedule-data)),
                  assigned-volunteer: none
                })
              )
            false
          )
          (print { event: "task-completed", task-id: task-id, volunteer: tx-sender, rating: quality-rating })
          (ok true)
        )
        ERR_UNAUTHORIZED
      )
    ERR_MAINTENANCE_NOT_FOUND
  )
)

;; Add maintenance supply
(define-public (add-supply (supply-name (string-ascii 50)) (quantity uint) (unit-cost uint) (supplier (string-ascii 100)) (minimum-threshold uint))
  (let ((supply-id (var-get next-supply-id)))
    (map-set maintenance-supplies
      { supply-id: supply-id }
      {
        supply-name: supply-name,
        quantity-available: quantity,
        unit-cost: unit-cost,
        supplier: supplier,
        last-restocked: block-height,
        minimum-threshold: minimum-threshold
      }
    )
    (var-set next-supply-id (+ supply-id u1))
    (print { event: "supply-added", supply-id: supply-id, name: supply-name, quantity: quantity })
    (ok supply-id)
  )
)

;; Read-only Functions

;; Get chime maintenance schedule
(define-read-only (get-maintenance-schedule (chime-id uint))
  (map-get? chime-maintenance-schedule { chime-id: chime-id })
)

;; Get task details
(define-read-only (get-task-details (task-id uint))
  (map-get? maintenance-tasks { task-id: task-id })
)

;; Get volunteer profile
(define-read-only (get-volunteer-profile (volunteer principal))
  (map-get? volunteer-profiles { volunteer: volunteer })
)

;; Get maintenance history
(define-read-only (get-maintenance-history (chime-id uint) (history-id uint))
  (map-get? maintenance-history { chime-id: chime-id, history-id: history-id })
)

;; Get supply details
(define-read-only (get-supply-details (supply-id uint))
  (map-get? maintenance-supplies { supply-id: supply-id })
)

;; Check if maintenance is overdue
(define-read-only (is-maintenance-overdue (chime-id uint))
  (match (map-get? chime-maintenance-schedule { chime-id: chime-id })
    schedule-data (> block-height (get next-scheduled schedule-data))
    false
  )
)

;; Get pending tasks for volunteer
(define-read-only (get-volunteer-tasks (volunteer principal))
  ;; In a full implementation, this would return a list of assigned tasks
  ;; For now, returning whether the volunteer exists
  (is-some (map-get? volunteer-profiles { volunteer: volunteer }))
)

;; Calculate maintenance priority
(define-read-only (calculate-maintenance-priority (chime-id uint))
  (match (map-get? chime-maintenance-schedule { chime-id: chime-id })
    schedule-data
      (let ((blocks-overdue (if (> block-height (get next-scheduled schedule-data))
                              (- block-height (get next-scheduled schedule-data))
                              u0)))
        (+ (get priority-level schedule-data) (/ blocks-overdue u100))
      )
    u0
  )
)

;; Administrative Functions

;; Update maintenance reward
(define-public (update-maintenance-reward (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set maintenance-reward-amount new-amount)
    (print { event: "reward-updated", new-amount: new-amount })
    (ok true)
  )
)

;; Cancel maintenance task
(define-public (cancel-task (task-id uint) (reason (string-ascii 100)))
  (match (map-get? maintenance-tasks { task-id: task-id })
    task-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set maintenance-tasks
          { task-id: task-id }
          (merge task-data { status: "cancelled" })
        )
        (print { event: "task-cancelled", task-id: task-id, reason: reason })
        (ok true)
      )
    ERR_MAINTENANCE_NOT_FOUND
  )
)

;; Update volunteer reliability score
(define-public (update-volunteer-reliability (volunteer principal) (new-score uint))
  (match (map-get? volunteer-profiles { volunteer: volunteer })
    volunteer-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-score u100) ERR_INVALID_SCHEDULE)
        (map-set volunteer-profiles
          { volunteer: volunteer }
          (merge volunteer-data { reliability-score: new-score })
        )
        (print { event: "reliability-updated", volunteer: volunteer, score: new-score })
        (ok true)
      )
    ERR_VOLUNTEER_NOT_AVAILABLE
  )
)
