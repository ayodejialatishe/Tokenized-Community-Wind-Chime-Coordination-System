;; Placement Optimization Contract
;; Determines ideal hanging locations for wind exposure

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_LOCATION_NOT_FOUND (err u301))
(define-constant ERR_INVALID_COORDINATES (err u302))
(define-constant ERR_LOCATION_OCCUPIED (err u303))
(define-constant ERR_INSUFFICIENT_WIND_EXPOSURE (err u304))

;; Data Variables
(define-data-var min-wind-exposure-score uint u30) ;; Minimum required wind exposure (0-100 scale)
(define-data-var max-chimes-per-area uint u5)

;; Data Maps
(define-map location-registry
  { location-id: uint }
  {
    coordinates: { x: uint, y: uint, z: uint },
    area-name: (string-ascii 100),
    wind-exposure-score: uint, ;; 0-100 scale
    environmental-factors: (string-ascii 200),
    registered-by: principal,
    registration-block: uint,
    available: bool
  }
)

(define-map chime-placements
  { chime-id: uint }
  {
    location-id: uint,
    placement-score: uint, ;; Overall placement quality score
    wind-direction-compatibility: uint, ;; 0-100 scale
    acoustic-interference: uint, ;; 0-100 scale (lower is better)
    aesthetic-rating: uint, ;; 0-100 scale
    placed-by: principal,
    placement-block: uint
  }
)

(define-map location-conflicts
  { location-id: uint, conflict-id: uint }
  {
    conflicting-chime-ids: (list 10 uint),
    conflict-type: (string-ascii 50),
    reported-by: principal,
    report-block: uint,
    resolution-status: (string-ascii 20), ;; "pending", "resolved", "escalated"
    resolution-details: (string-ascii 200)
  }
)

(define-map wind-patterns
  { area-id: uint }
  {
    area-name: (string-ascii 100),
    dominant-wind-direction: uint, ;; 0-360 degrees
    average-wind-speed: uint, ;; km/h
    seasonal-variations: (string-ascii 100),
    measurement-date: uint,
    measured-by: principal
  }
)

(define-map placement-recommendations
  { chime-id: uint }
  {
    recommended-locations: (list 5 uint),
    recommendation-score: uint,
    factors-considered: (string-ascii 200),
    generated-by: principal,
    generation-block: uint,
    accepted: bool
  }
)

;; Data Lists
(define-data-var next-location-id uint u1)
(define-data-var next-conflict-id uint u1)
(define-data-var next-area-id uint u1)

;; Public Functions

;; Register a new location
(define-public (register-location (coordinates-x uint) (coordinates-y uint) (coordinates-z uint) (area-name (string-ascii 100)) (wind-exposure-score uint) (environmental-factors (string-ascii 200)))
  (let ((location-id (var-get next-location-id)))
    (asserts! (<= wind-exposure-score u100) ERR_INVALID_COORDINATES)
    (map-set location-registry
      { location-id: location-id }
      {
        coordinates: { x: coordinates-x, y: coordinates-y, z: coordinates-z },
        area-name: area-name,
        wind-exposure-score: wind-exposure-score,
        environmental-factors: environmental-factors,
        registered-by: tx-sender,
        registration-block: block-height,
        available: true
      }
    )
    (var-set next-location-id (+ location-id u1))
    (print { event: "location-registered", location-id: location-id, area: area-name })
    (ok location-id)
  )
)

;; Place chime at location
(define-public (place-chime (chime-id uint) (location-id uint) (wind-direction-compatibility uint) (acoustic-interference uint) (aesthetic-rating uint))
  (let ((location-data (unwrap! (map-get? location-registry { location-id: location-id }) ERR_LOCATION_NOT_FOUND)))
    (asserts! (get available location-data) ERR_LOCATION_OCCUPIED)
    (asserts! (>= (get wind-exposure-score location-data) (var-get min-wind-exposure-score)) ERR_INSUFFICIENT_WIND_EXPOSURE)
    (asserts! (<= wind-direction-compatibility u100) ERR_INVALID_COORDINATES)
    (asserts! (<= acoustic-interference u100) ERR_INVALID_COORDINATES)
    (asserts! (<= aesthetic-rating u100) ERR_INVALID_COORDINATES)

    (let ((placement-score (/ (+ wind-direction-compatibility (- u100 acoustic-interference) aesthetic-rating) u3)))
      (map-set chime-placements
        { chime-id: chime-id }
        {
          location-id: location-id,
          placement-score: placement-score,
          wind-direction-compatibility: wind-direction-compatibility,
          acoustic-interference: acoustic-interference,
          aesthetic-rating: aesthetic-rating,
          placed-by: tx-sender,
          placement-block: block-height
        }
      )
      ;; Mark location as occupied
      (map-set location-registry
        { location-id: location-id }
        (merge location-data { available: false })
      )
      (print { event: "chime-placed", chime-id: chime-id, location-id: location-id, score: placement-score })
      (ok placement-score)
    )
  )
)

;; Report location conflict
(define-public (report-conflict (location-id uint) (conflicting-chimes (list 10 uint)) (conflict-type (string-ascii 50)))
  (let ((conflict-id (var-get next-conflict-id)))
    (unwrap! (map-get? location-registry { location-id: location-id }) ERR_LOCATION_NOT_FOUND)
    (map-set location-conflicts
      { location-id: location-id, conflict-id: conflict-id }
      {
        conflicting-chime-ids: conflicting-chimes,
        conflict-type: conflict-type,
        reported-by: tx-sender,
        report-block: block-height,
        resolution-status: "pending",
        resolution-details: ""
      }
    )
    (var-set next-conflict-id (+ conflict-id u1))
    (print { event: "conflict-reported", location-id: location-id, conflict-id: conflict-id })
    (ok conflict-id)
  )
)

;; Record wind pattern data
(define-public (record-wind-pattern (area-name (string-ascii 100)) (wind-direction uint) (wind-speed uint) (seasonal-variations (string-ascii 100)))
  (let ((area-id (var-get next-area-id)))
    (asserts! (<= wind-direction u360) ERR_INVALID_COORDINATES)
    (map-set wind-patterns
      { area-id: area-id }
      {
        area-name: area-name,
        dominant-wind-direction: wind-direction,
        average-wind-speed: wind-speed,
        seasonal-variations: seasonal-variations,
        measurement-date: block-height,
        measured-by: tx-sender
      }
    )
    (var-set next-area-id (+ area-id u1))
    (print { event: "wind-pattern-recorded", area-id: area-id, direction: wind-direction })
    (ok area-id)
  )
)

;; Generate placement recommendation
(define-public (generate-recommendation (chime-id uint) (recommended-locations (list 5 uint)) (factors-considered (string-ascii 200)))
  (let ((recommendation-score (calculate-recommendation-score recommended-locations)))
    (map-set placement-recommendations
      { chime-id: chime-id }
      {
        recommended-locations: recommended-locations,
        recommendation-score: recommendation-score,
        factors-considered: factors-considered,
        generated-by: tx-sender,
        generation-block: block-height,
        accepted: false
      }
    )
    (print { event: "recommendation-generated", chime-id: chime-id, score: recommendation-score })
    (ok recommendation-score)
  )
)

;; Remove chime from location
(define-public (remove-chime (chime-id uint))
  (match (map-get? chime-placements { chime-id: chime-id })
    placement-data
      (let ((location-id (get location-id placement-data)))
        (match (map-get? location-registry { location-id: location-id })
          location-data
            (begin
              (map-delete chime-placements { chime-id: chime-id })
              (map-set location-registry
                { location-id: location-id }
                (merge location-data { available: true })
              )
              (print { event: "chime-removed", chime-id: chime-id, location-id: location-id })
              (ok true)
            )
          ERR_LOCATION_NOT_FOUND
        )
      )
    ERR_LOCATION_NOT_FOUND
  )
)

;; Read-only Functions

;; Get location details
(define-read-only (get-location-details (location-id uint))
  (map-get? location-registry { location-id: location-id })
)

;; Get chime placement details
(define-read-only (get-placement-details (chime-id uint))
  (map-get? chime-placements { chime-id: chime-id })
)

;; Get conflict details
(define-read-only (get-conflict-details (location-id uint) (conflict-id uint))
  (map-get? location-conflicts { location-id: location-id, conflict-id: conflict-id })
)

;; Get wind pattern data
(define-read-only (get-wind-pattern (area-id uint))
  (map-get? wind-patterns { area-id: area-id })
)

;; Get placement recommendation
(define-read-only (get-recommendation (chime-id uint))
  (map-get? placement-recommendations { chime-id: chime-id })
)

;; Calculate optimal placement score
(define-read-only (calculate-placement-score (wind-exposure uint) (acoustic-quality uint) (aesthetic-value uint))
  (/ (+ wind-exposure acoustic-quality aesthetic-value) u3)
)

;; Find available locations with minimum wind exposure
(define-read-only (find-suitable-locations (min-wind-score uint))
  ;; This would return a list of suitable location IDs in a real implementation
  ;; For now, returning a simple boolean check
  (>= min-wind-score (var-get min-wind-exposure-score))
)

;; Private Functions

;; Calculate recommendation score based on location quality
(define-private (calculate-recommendation-score (locations (list 5 uint)))
  ;; Simplified calculation - in practice would analyze each location
  (let ((location-count (len locations)))
    (if (> location-count u0)
      (* location-count u20) ;; Base score of 20 per recommended location
      u0
    )
  )
)

;; Administrative Functions

;; Update minimum wind exposure requirement
(define-public (update-min-wind-exposure (new-minimum uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-minimum u100) ERR_INVALID_COORDINATES)
    (var-set min-wind-exposure-score new-minimum)
    (print { event: "min-wind-exposure-updated", new-minimum: new-minimum })
    (ok true)
  )
)

;; Resolve location conflict
(define-public (resolve-conflict (location-id uint) (conflict-id uint) (resolution-details (string-ascii 200)))
  (match (map-get? location-conflicts { location-id: location-id, conflict-id: conflict-id })
    conflict-data
      (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set location-conflicts
          { location-id: location-id, conflict-id: conflict-id }
          (merge conflict-data {
            resolution-status: "resolved",
            resolution-details: resolution-details
          })
        )
        (print { event: "conflict-resolved", location-id: location-id, conflict-id: conflict-id })
        (ok true)
      )
    ERR_LOCATION_NOT_FOUND
  )
)
