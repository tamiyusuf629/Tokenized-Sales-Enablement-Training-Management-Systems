;; Training Program Management System
;; Handles creation, enrollment, and management of sales training programs

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_PROGRAM_NOT_FOUND (err u201))
(define-constant ERR_ALREADY_ENROLLED (err u202))
(define-constant ERR_NOT_ENROLLED (err u203))
(define-constant ERR_INVALID_PROGRAM_DATA (err u204))
(define-constant ERR_PROGRAM_FULL (err u205))

;; Data structures
(define-map training-programs
  { program-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    trainer-id: principal,
    duration-weeks: uint,
    max-participants: uint,
    current-participants: uint,
    skill-level: (string-ascii 20),
    price-tokens: uint,
    created-at: uint,
    active: bool
  }
)

(define-map program-modules
  { program-id: uint, module-id: uint }
  {
    title: (string-ascii 100),
    content-hash: (string-ascii 64),
    duration-hours: uint,
    learning-objectives: (list 5 (string-ascii 200)),
    assessment-required: bool
  }
)

(define-map enrollments
  { program-id: uint, participant-id: principal }
  {
    enrollment-date: uint,
    progress-percentage: uint,
    modules-completed: (list 20 uint),
    current-module: uint,
    completion-date: uint,
    final-score: uint,
    status: (string-ascii 20)
  }
)

(define-data-var next-program-id uint u1)
(define-data-var total-programs uint u0)
(define-data-var total-enrollments uint u0)

;; Public functions
(define-public (create-training-program
  (title (string-ascii 100))
  (description (string-ascii 500))
  (duration-weeks uint)
  (max-participants uint)
  (skill-level (string-ascii 20))
  (price-tokens uint)
)
  (let ((program-id (var-get next-program-id)))
    (asserts! (> (len title) u0) ERR_INVALID_PROGRAM_DATA)
    (asserts! (> duration-weeks u0) ERR_INVALID_PROGRAM_DATA)
    (asserts! (> max-participants u0) ERR_INVALID_PROGRAM_DATA)

    (map-set training-programs
      { program-id: program-id }
      {
        title: title,
        description: description,
        trainer-id: tx-sender,
        duration-weeks: duration-weeks,
        max-participants: max-participants,
        current-participants: u0,
        skill-level: skill-level,
        price-tokens: price-tokens,
        created-at: block-height,
        active: true
      }
    )

    (var-set next-program-id (+ program-id u1))
    (var-set total-programs (+ (var-get total-programs) u1))

    (ok program-id)
  )
)

(define-public (add-program-module
  (program-id uint)
  (module-id uint)
  (title (string-ascii 100))
  (content-hash (string-ascii 64))
  (duration-hours uint)
  (learning-objectives (list 5 (string-ascii 200)))
  (assessment-required bool)
)
  (let ((program-data (unwrap! (map-get? training-programs { program-id: program-id }) ERR_PROGRAM_NOT_FOUND)))
    (asserts! (is-eq (get trainer-id program-data) tx-sender) ERR_UNAUTHORIZED)

    (map-set program-modules
      { program-id: program-id, module-id: module-id }
      {
        title: title,
        content-hash: content-hash,
        duration-hours: duration-hours,
        learning-objectives: learning-objectives,
        assessment-required: assessment-required
      }
    )

    (ok module-id)
  )
)

(define-public (enroll-in-program (program-id uint))
  (let ((program-data (unwrap! (map-get? training-programs { program-id: program-id }) ERR_PROGRAM_NOT_FOUND)))
    (asserts! (get active program-data) ERR_UNAUTHORIZED)
    (asserts! (< (get current-participants program-data) (get max-participants program-data)) ERR_PROGRAM_FULL)
    (asserts! (is-none (map-get? enrollments { program-id: program-id, participant-id: tx-sender })) ERR_ALREADY_ENROLLED)

    (map-set enrollments
      { program-id: program-id, participant-id: tx-sender }
      {
        enrollment-date: block-height,
        progress-percentage: u0,
        modules-completed: (list),
        current-module: u1,
        completion-date: u0,
        final-score: u0,
        status: "enrolled"
      }
    )

    (map-set training-programs
      { program-id: program-id }
      (merge program-data {
        current-participants: (+ (get current-participants program-data) u1)
      })
    )

    (var-set total-enrollments (+ (var-get total-enrollments) u1))

    (ok true)
  )
)

(define-public (complete-module (program-id uint) (module-id uint))
  (let ((enrollment-data (unwrap! (map-get? enrollments { program-id: program-id, participant-id: tx-sender }) ERR_NOT_ENROLLED)))
    (asserts! (is-eq (get status enrollment-data) "enrolled") ERR_UNAUTHORIZED)

    (let ((updated-modules (unwrap-panic (as-max-len? (append (get modules-completed enrollment-data) module-id) u20))))
      (map-set enrollments
        { program-id: program-id, participant-id: tx-sender }
        (merge enrollment-data {
          modules-completed: updated-modules,
          current-module: (+ module-id u1),
          progress-percentage: (/ (* (len updated-modules) u100) u10) ;; Assuming 10 modules per program
        })
      )
    )

    (ok module-id)
  )
)

(define-public (complete-program (program-id uint) (final-score uint))
  (let ((enrollment-data (unwrap! (map-get? enrollments { program-id: program-id, participant-id: tx-sender }) ERR_NOT_ENROLLED)))
    (asserts! (is-eq (get status enrollment-data) "enrolled") ERR_UNAUTHORIZED)
    (asserts! (<= final-score u100) ERR_INVALID_PROGRAM_DATA)

    (map-set enrollments
      { program-id: program-id, participant-id: tx-sender }
      (merge enrollment-data {
        completion-date: block-height,
        final-score: final-score,
        progress-percentage: u100,
        status: "completed"
      })
    )

    (ok final-score)
  )
)

;; Read-only functions
(define-read-only (get-program-info (program-id uint))
  (map-get? training-programs { program-id: program-id })
)

(define-read-only (get-program-module (program-id uint) (module-id uint))
  (map-get? program-modules { program-id: program-id, module-id: module-id })
)

(define-read-only (get-enrollment-info (program-id uint) (participant-id principal))
  (map-get? enrollments { program-id: program-id, participant-id: participant-id })
)

(define-read-only (get-total-programs)
  (var-get total-programs)
)

(define-read-only (get-total-enrollments)
  (var-get total-enrollments)
)
