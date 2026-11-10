;;; --------------------------------------------------------
;;; Spread development of harmonic IDs
;;;
;;; A development over time in which the IDs are spread:
;;; each row is one event with LEN voices whose IDs lie
;;; f apart (0, f, 2f, 3f ...). The spread factor f
;;; follows an xy envelope, so the IDs fan out from a
;;; unison (f = 0) and draw together again. Added to a
;;; transposition, the IDs are positions in the pitch
;;; material; ID 0 is its lowest note.
;;;
;;; spread-develop-om -- original, with Opusmodus functions
;;; spread-develop    -- plain Common Lisp, same interface
;;; env-y-at          -- one y value of an xy envelope
;;; env-samples-y     -- N evenly spaced y values
;;; noise-at          -- seeded noise value for one row
;;; --------------------------------------------------------

;;; --------------------------------------------------------
;;; Variant A -- with Opusmodus functions
;;; --------------------------------------------------------

(defun spread-develop-om (len env &key (variance 0.0)
                                       steps round seed)
  "Development in which LEN IDs are spread: row by row, the
IDs 0 ... LEN-1 are multiplied by a spread factor that
follows an xy envelope.
ENV '(x1 y1 x2 y2 ...): x = step index, y = spread factor.
By default one row per integer x step; STEPS overrides that
count, and the x values then act as mere proportions.
VARIANCE: a number, or its own xy envelope -- it is
resampled to the same count, so its x range does not matter.
Ex.:
 (spread-develop-om 5 '(0 0 5 2 12 3 15 1 20 0) :round t)
 (spread-develop-om 5 '(0 0 1 2 2.4 3 3 1 4 0) :steps 40)"
  (let* ((base  (gen-integer 0 (1- len)))
         (n     (or steps (1+ (- (car (last env 2))
                                 (first env)))))
         (curve (envelope-y (envelope-samples env n)))
         (vars  (if (listp variance)
                    (envelope-y
                     (envelope-samples variance n))
                    (make-list n
                               :initial-element variance)))
         (noise (rnd-number n -1.0 1.0 :seed seed)))
    (loop for f in curve
          for v in vars
          for r in noise
          for d = (+ 1.0 (* v r))
          for row = (mapcar (lambda (y) (* y f d)) base)
          collect (if round (mapcar #'round row) row))))

;;; --------------------------------------------------------
;;; Variant B -- plain Common Lisp
;;;
;;; Same interface and computation. Two parts had to be
;;; rebuilt:
;;; - envelope resampling: N evenly spaced points from the
;;;   first to the last x, both ends included, linearly
;;;   interpolated (the behaviour the docstring of the
;;;   Opusmodus version relies on);
;;; - noise: a seeded 32-bit hash of SEED and the row
;;;   number, so a given SEED repeats in every Lisp. It is
;;;   NOT the sequence RND-NUMBER gives for the same SEED.
;;; With VARIANCE 0 both variants should return the same
;;; rows -- see the check at the end of the file.
;;; --------------------------------------------------------

(defun env-y-at (env x)
  "Y value of the xy envelope ENV '(x1 y1 x2 y2 ...) at X,
linearly interpolated. Beyond either end the end value
holds. Two points with the same x make a vertical jump."
  (if (<= x (first env))
      (second env)
      (loop for (xa ya xb yb) on env by #'cddr
            while xb
            when (<= x xb)
              do (return
                   (if (= xa xb)
                       yb
                       (+ ya (/ (* (- yb ya) (- x xa))
                                (- xb xa)))))
            finally (return (car (last env))))))

(defun env-samples-y (env n)
  "N evenly spaced y values of the xy envelope ENV, from
its first to its last x, both ends included."
  (let ((x0 (first env))
        (x1 (car (last env 2))))
    (loop for i below n
          collect (env-y-at
                   env
                   (if (= n 1)
                       x0
                       (+ x0 (/ (* i (- x1 x0))
                                (1- n))))))))

(defun noise-at (seed i)
  "Number from -1.0 to 1.0 for row I, fully determined by
the integer SEED. A 32-bit integer hash (murmur3
finalizer): neighbouring rows and seeds give unrelated
values."
  (flet ((u32 (x) (logand x #xFFFFFFFF)))
    (let ((h (u32 (+ (* seed #x9E3779B9) i))))
      (setf h (u32 (* (logxor h (ash h -16))
                      #x85EBCA6B))
            h (u32 (* (logxor h (ash h -13))
                      #xC2B2AE35))
            h (logxor h (ash h -16)))
      (- (* 2.0 (/ h #xFFFFFFFF)) 1.0))))

(defun spread-develop (len env &key (variance 0.0)
                                    steps round seed)
  "Plain Common Lisp version of SPREAD-DEVELOP-OM.
Development in which LEN IDs are spread: row by row, the
IDs 0 ... LEN-1 are multiplied by a spread factor that
follows an xy envelope.
ENV '(x1 y1 x2 y2 ...): x = step index, y = spread factor.
By default one row per integer x step; STEPS overrides that
count, and the x values then act as mere proportions.
VARIANCE: a number, or its own xy envelope -- resampled to
the same count, so its x range does not matter.
SEED: an integer for repeatable noise (a different
sequence from Opusmodus RND-NUMBER).
Ex.:
 (spread-develop 5 '(0 0 5 2 12 3 15 1 20 0) :round t)
 (spread-develop 5 '(0 0 1 2 2.4 3 3 1 4 0) :steps 40)"
  (let* ((n     (or steps
                    (1+ (floor (- (car (last env 2))
                                  (first env))))))
         (curve (env-samples-y env n))
         (vars  (if (consp variance)
                    (env-samples-y variance n)
                    (make-list n
                               :initial-element variance))))
    (loop for i below n
          for f in curve
          for v in vars
          for r = (if seed
                      (noise-at seed i)
                      (- (random 2.0) 1.0))
          for d = (+ 1.0 (* v r))
          collect (loop for y below len
                        for x = (* y f d)
                        collect (if round (round x) x)))))

;;; --------------------------------------------------------
;;; Usage -- Opusmodus
;;; --------------------------------------------------------

#|
;; EVENTS is set earlier in the score, e.g.
(setf events 11)

;; Transposition envelope as offset
;; for the chord progression
(setf transp-env '(0 2 10 2 20 3 30 4 40 3 50 6
                   60 4 70 0 80 1 90 2 100 3))

(list-plot
 ;; List of integer transpositions according to the
 ;; number of events
 (setf transp
       (mapcar #'round
               (envelope-y
                (envelope-samples transp-env events))))
 :join-points t)

;; Development of selections from the pitch material
;; (0 0 0 0 0 0 0 0 0) = unison
;; (0 1 2 3 4 5 6 7 8) = successive pitches in scale
;; (0 2 4 6 8 10 12 14 16) = every second pitch in scale
(setf spread
      (spread-develop-om
       9 '(0 0 30 1 70 4 100 1) :steps events :round t))

;; Add transposition to it
(setf indexes
      (loop for i in transp
            for j in spread
            collect (integer-transpose i j)))

;; Convert to voices from high to low
(list-plot
 (setf voice-ids
       (reverse
        (matrix-transpose
         indexes)))
 :join-points t)
|#

;;; --------------------------------------------------------
;;; Usage -- plain Common Lisp, same chain
;;; --------------------------------------------------------

#|
(defparameter *events* 11)

(defparameter *transp*
  (mapcar #'round
          (env-samples-y '(0 2 10 2 20 3 30 4 40 3 50 6
                           60 4 70 0 80 1 90 2 100 3)
                         *events*)))

(defparameter *spread*
  (spread-develop 9 '(0 0 30 1 70 4 100 1)
                  :steps *events* :round t))

(defparameter *indexes*
  (loop for tr in *transp*
        for row in *spread*
        collect (mapcar (lambda (id) (+ id tr)) row)))

;; voices from high to low
(defparameter *voice-ids*
  (reverse (apply #'mapcar #'list *indexes*)))
|#

;;; --------------------------------------------------------
;;; Check in Opusmodus: both variants, variance 0
;;; --------------------------------------------------------

#|
(let ((env '(0 0 30 1 70 4 100 1)))
  (list
   :envelope
   (every (lambda (a b) (< (abs (- a b)) 1e-5))
          (envelope-y (envelope-samples env 23))
          (env-samples-y env 23))
   :rows
   (equal (spread-develop-om 9 env :steps 23 :round t)
          (spread-develop 9 env :steps 23 :round t))))
;; => (:ENVELOPE T :ROWS T) if ENVELOPE-SAMPLES samples
;;    the way the plain version assumes
|#

;; 1 -- constant amount of deviation
(spread-develop 5 '(0 0 5 2 12 3 15 1 20 0)
                :variance 0.2 :round t :seed 42)

;; 2 -- deviation as its own envelope: calm at the edges,
;; restless around the peak
(spread-develop 5 '(0 0 5 2 12 3 15 1 20 0)
                :variance '(0 0.0 8 0.05 12 0.4 20 0.0)
                :round t :seed 42)

;; 3 -- growing unrest: steady start, wild ending
(spread-develop 7 '(0 0 10 3 20 0) :steps 40
                :variance '(0 0.0 1 0.6) :round t :seed 3)

;; 4 -- the x range of the variance envelope is irrelevant,
;; it is resampled to the same count; both give the same:
(spread-develop 5 '(0 0 5 2 12 3 15 1 20 0)
                :variance '(0 0.0 1 0.4 2 0.0) :seed 7)
(spread-develop 5 '(0 0 5 2 12 3 15 1 20 0)
                :variance '(0 0.0 100 0.4 200 0.0) :seed 7)
