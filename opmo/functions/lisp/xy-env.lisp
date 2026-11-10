(defun xy-env (alist &key env-ids) 
"Turn a list of y-values into a flat x/y envelope 
(breakpoint list). Without ENV-IDS the x-values are 
consecutive integers from 0 to n-1. With ENV-IDS the 
x-values are spread evenly over the range 0 to ENV-IDS-1 
(rounded), so the envelope is scaled to an envelope 
grid of that size.
Ex.:
(xy-env '(10 20 30)) => (0 10 1 20 2 30)
(xy-env '(10 20 30) :env-ids 10) => (0 10 4 20 9 30)"
  (let* ((y-values-length (- (length alist) 1))
         (x-values (if env-ids
                       (gen-transition 
                        0 (- env-ids 1) (length alist)  1
                        :rounded t)
                     (gen-integer 0 y-values-length))))
    (loop for x in x-values
          for y in alist
          collect x 
          collect y)))

(defun max-length (lists)
  "Get the maximum length of lists."
  (first (sort (mapcar #'length lists) #'>)))

(defun xy-envs (lists)
  "Make a list of xy-envelopes from several lists
according to the longest one."
  (let ((max-len (max-length lists)))
    (loop for i in lists
            collect (xy-env i :env-ids max-len))))

(defun omn-to-xy (omn)
  "Convert omn lengths to legato durations and dechorded
pitches to midi as numerical x-y data for xy-plot display."
  (make-xy
   (cons 0.0 (ratio-to-float
              (cumulative-sums
               (length-legato
                (omn :length omn)))))
   (pitch-to-midi (dechord
                   (append
                    (omn :pitch omn)
                    (last (omn :pitch omn)))))))

(setf voc1
      (make-omn
       :length '(1/16 1/8 1/16 1/16 -1/8 1/16 1/16 1/4 1/16 1/8)
       :pitch '(g4 g4 cs5 c4 fs5 g4 g4 gs5 gs5)
       :velocity '(pp pp pp pp pp mf mf mp mp)))

(setf voc2
      (make-omn
       :length 
       (rnd-order 
        '(1/16 1/8 1/16 1/16 -1/8 1/16 1/16 1/4 1/16 1/8))
       :pitch (rnd-order 
               '(g4 g4 cs5 c4 fs5 g4 g4 gs5 gs5))
       :velocity '(pp pp pp pp pp mf mf mp mp)))

;; Plot all voices
(xy-plot
 (list
  (omn-to-xy voc1)
  (omn-to-xy voc2))
 :join-points t)