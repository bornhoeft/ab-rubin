;;; --------------------------------------------------------
;;; Variable-length list of ratios with fixed sum, fixed
;;; minimum and maximum, snapped to a quantize grid
;;;
;;; grid-unit       -- smallest common unit of a quantize
;;;                    list
;;; fix-rounding    -- scale + snap + repair the sum
;;;                    (shared part)
;;; check-sum-range -- is the target sum reachable at all?
;;; fit-sum         -- plain Common Lisp
;;; fit-sum-om      -- same computation with
;;;                    gen-transition / vector-map
;;;
;;; Everything stays rational: the values are scaled to the
;;; target sum, snapped to the grid and the remainder is
;;; distributed, so the sum is exact by construction.

;;; https://claude.ai/artifact/JnUzXZ3zWWG1xYc6FnqbHa

;;; --------------------------------------------------------

(defun grid-unit (quantize)
  "Smallest common time unit of a QUANTIZE list.
'(1 2 4) => 1/4, '(1 2 4 8) => 1/8, '(1 2 3) => 1/6."
  (/ 1 (reduce #'lcm quantize)))

(defun fix-rounding (values total &key (quantize '(1 2 4))
                                       min max)
  "Scales VALUES (ratios) so their sum is TOTAL, snaps every
value to the grid given by QUANTIZE and distributes the
rounding remainder, so that the sum is EXACTLY TOTAL --
one grid unit at a time, first where the rounding error was
largest, and only within MIN ... MAX.
MIN/MAX are ratios; MIN defaults to one grid unit, so no
value can collapse to zero.
Ex.:
 (fix-rounding '(1/4 1/8 1/4 3/4 1 3/8) 4
               :quantize '(1 2 4))
 => (1/2 1/4 1/4 1 3/2 1/2)
 (fix-rounding '(1/4 1/8 1/4 3/4 1 3/8) 4
               :quantize '(1 2 4 8))
 => (3/8 1/8 3/8 9/8 3/2 1/2)"
  (let* ((unit  (grid-unit quantize))
         (steps (round (/ total unit)))
         (lo    (if min (max 1 (ceiling (/ min unit))) 1))
         (hi    (if max (floor (/ max unit)) steps))
         (raw   (let ((s (reduce #'+ values)))
                  (mapcar (lambda (x)
                            (/ (* x total) s unit))
                          values)))
         (n     (length raw))
         (ints  (mapcar (lambda (x)
                          (min hi (max lo (floor x))))
                        raw)))
    (assert (<= (* n lo) steps (* n hi)) (total)
            "~a units cannot be split into ~a values ~
             between ~a and ~a units."
            steps n lo hi)
        (loop for rest = (- steps (reduce #'+ ints))
          for moved = 0
          while (/= rest 0)
          do (let ((err (mapcar #'- raw ints)))
               (loop for i in (sort (loop for k from 0
                                          below n
                                          collect k)
                                    (if (plusp rest)
                                        #'> #'<)
                                    :key (lambda (k)
                                           (nth k err)))
                     while (/= rest 0)
                     do (let ((d (if (plusp rest) 1 -1)))
                          (when (<= lo (+ (nth i ints) d)
                                    hi)
                            (incf (nth i ints) d)
                            (decf rest d)
                            (incf moved))))
               (when (zerop moved)
                 (error "~a units left over -- MIN/MAX ~
                         block any further correction."
                        rest))))
    (mapcar (lambda (i) (* i unit)) ints)))

(defun check-sum-range (n total min max quantize)
  "Early check -- fails before the bisection is run, and
reports the reachable range in ratios rather than in units."
  (let* ((unit  (grid-unit quantize))
         (lo    (max 1 (ceiling (/ min unit))))
         (hi    (floor (/ max unit)))
         (steps (round (/ total unit))))
    (assert (<= (* n lo) steps (* n hi)) (total)
            "Sum ~a not reachable: ~a values from ~a to ~a ~
             on a ~a grid give ~a ... ~a."
            total n min max unit
            (* n lo unit) (* n hi unit))))

;;; --------------------------------------------------------
;;; Variant A -- plain Common Lisp
;;;
;;; Normalise the contour to 0.0 ... 1.0, then
;;;   value = min + (max - min) * s^gamma
;;; s=0 always gives min, s=1 always max -- the extremes
;;; do not depend on gamma. Gamma changes only the
;;; curvature and with it the sum, and is tuned to the
;;; target sum by bisection. fix-rounding then does the
;;; last, exact step onto the grid.
;;; --------------------------------------------------------

(defun fit-sum (n total &key (min 1/8) (max 1)
                             (quantize '(1 2 4 8)) shape)
  "N ratios with sum TOTAL, smallest value MIN, largest
value MAX, all lying on the QUANTIZE grid.
SHAPE is any contour of length N;
default: (half-sine n 1 :phase 180)."
  (check-sum-range n total min max quantize)
  (let* ((raw (or shape (half-sine n 1 :phase 180)))
         (a (reduce #'min raw))
         (b (reduce #'max raw))
         (s (if (= a b)
                (make-list n :initial-element 0.5d0)
                (mapcar (lambda (x)
                          (coerce (/ (- x a) (- b a))
                                  'double-float))
                        raw)))
         (curve (lambda (g)
                  (mapcar (lambda (x)
                            (+ min (* (- max min)
                                      (expt x g))))
                          s)))
         (gamma (let ((g1 1d-4) (g2 1d4))
                  (dotimes (i 200 (sqrt (* g1 g2)))
                    (let ((m (sqrt (* g1 g2))))
                      (if (> (reduce #'+ (funcall curve m))
                             total)
                          (setf g1 m)
                          (setf g2 m)))))))
    (fix-rounding (funcall curve gamma) total
                  :quantize quantize :min min :max max)))

;;; --------------------------------------------------------
;;; Variant B -- with Opusmodus functions
;;;
;;; The same computation, but here the original chain does
;;; the work: gen-transition supplies the value table from
;;; MIN to MAX (its fourth parameter, the exponent, is the
;;; curvature control), vector-map maps the contour onto it.
;;; Only the exponent has to be found.
;;; RESOLUTION is nothing but the fineness of that table --
;;; the grid of the result comes from QUANTIZE.
;;; --------------------------------------------------------

(defun fit-sum-om (n total &key (min 1/8) (max 1)
                                (quantize '(1 2 4 8)) shape
                                (resolution 1000))
  (check-sum-range n total min max quantize)
  (let* ((sh (or shape (half-sine n 1 :phase 180)))
         (vals (lambda (e)
                 (vector-map (gen-transition
                              (float min) (float max)
                              resolution e)
                             sh)))
         (total-at (lambda (e)
                     (reduce #'+ (funcall vals e))))
         ;; determine the direction -- independent of the
         ;; exponent convention
         (down (> (funcall total-at 0.01)
                  (funcall total-at 100.0)))
         (e (let ((a 0.01) (b 100.0))
              (dotimes (i 100 (sqrt (* a b)))
                (let ((m (sqrt (* a b))))
                  (if (eq (> (funcall total-at m) total)
                          down)
                      (setf a m)
                      (setf b m)))))))
    (fix-rounding (funcall vals e) total
                  :quantize quantize :min min :max max)))

;;; --------------------------------------------------------
;;; Usage
;;; --------------------------------------------------------

;; The shared part on its own -- any list of ratios onto a
;; grid, with an exact sum:
(fix-rounding '(1/4 1/8 1/4 3/4 1 3/8) 4 :quantize '(1 2 4))
;; => (1/2 1/4 1/4 1 3/2 1/2)
(fix-rounding '(1/4 1/8 1/4 3/4 1 3/8) 4
              :quantize '(1 2 4 8))
;; => (3/8 1/8 3/8 9/8 3/2 1/2)

;; 20 values, 8 measures of 4/4, 1/8 ... 1,
;; on an eighth grid:
(fit-sum 20 8)
(fit-sum-om 20 8)

;; Number of values freely selectable -- sum, min, max and
;; grid stay:
(fit-sum 12 8)
(fit-sum 16 8)
(fit-sum 24 8)
(fit-sum 40 8)

;; For sum 8 with min 1/8 / max 1 on a 1/8 grid,
;; n from 8 to 64 works.

;; Sixteenth grid -- the contour survives more of its
;; detail:
(fit-sum 24 8 :quantize '(1 2 4 8 16) :min 1/16)

;; Triplet grid:
(fit-sum 18 6 :quantize '(1 2 3 6) :min 1/6 :max 1)

;; Different contour, same conditions:
(fit-sum 20 8 :shape (gen-sine 20 1 1))
(fit-sum 20 8 :shape (half-sine 20 1 :phase 0))
(fit-sum 20 8 :shape (rnd-sample 20 (gen-integer 0 12)))

;; Integers as before -- grid '(1) and integer bounds:
(fit-sum 20 90 :quantize '(1) :min 1 :max 10)

;; Straight into a score:
(make-omn :length (fit-sum 20 8)
          :pitch (rnd-sample 20 '(c4 d4 e4 g4 a4)))

;; Check:
#|
(let ((x (fit-sum 24 8)))
(list :sum (reduce #'+ x)
         :min (reduce #'min x)
         :max (reduce #'max x)))
 (list-plot (fit-sum 40 8) :join-points t)
|#


(fit-sum 100 200 :quantize '(1 2 4) :min 1/2 :max 3)
