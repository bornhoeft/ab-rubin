;;; ============================================================================
;;;  gen-asym-sine  –  Sinuswelle mit gleichzeitiger Amplituden- und
;;;                    Offset-Modulation sowie einstellbarer Asymmetrie
;;;  Achim Bornhöft / SEM – Common Lisp (Opusmodus-kompatibel)
;;; ============================================================================

(defun %sample-mod (m T01)
  "Wertet einen Modulator M an der normierten Zeit T01 (0..1) aus.
   M darf sein:  eine Zahl (konstant),
                 eine Breakpoint-Liste (linear interpoliert über die Dauer),
                 oder eine Funktion (T01) -> Zahl."
  (cond
    ((functionp m) (funcall m T01))
    ((consp m)
     (let ((len (length m)))
       (if (= len 1)
           (float (first m) 1d0)
           (let* ((pos  (* T01 (1- len)))
                  (i    (min (floor pos) (- len 2)))
                  (frac (- pos i))
                  (a    (float (nth i m) 1d0))
                  (b    (float (nth (1+ i) m) 1d0)))
             (+ (* a (- 1d0 frac)) (* b frac))))))
    (t (float m 1d0))))

(defun gen-asym-sine (n &key (freq 5.0) (dur 1.0)
                             (amp 1.0) (offset 0.0)
                             (asym 0.0) (skew 0.0) (phase 0.0))
  "Erzeugt eine Liste mit N Werten einer Sinuswelle, deren AMPLITUDE und
   OFFSET gleichzeitig moduliert werden. Zusätzlich zwei unabhängige
   Asymmetrie-Achsen:

     N       Anzahl der Werte in der Ergebnisliste
     FREQ    Frequenz in Hz  (= Zyklen pro DUR Sekunden)
     DUR     Gesamtdauer in Sekunden  (FREQ*DUR = Anzahl Zyklen über N)
     AMP     Amplitude  – Zahl, Breakpoint-Liste oder Funktion (t in 0..1)
     OFFSET  additiver Offset (DC) – Zahl, Breakpoint-Liste oder Funktion
     ASYM    vertikale Asymmetrie  [-1..1]  (Berge vs. Täler)
     SKEW    horizontale Asymmetrie (-1..1) (Anstieg vs. Abfall / Lage des
             Scheitels – so 'lehnen' die Wellenberge wie in der Zeichnung)
     PHASE   Startphase in Zyklen (0 = Sinus startet bei 0, steigend)

   AMP, OFFSET, ASYM und SKEW dürfen jeweils zeitvariabel sein
   (Breakpoint-Liste oder Funktion)."
  (let ((cycles (* freq dur))
        (out    '()))
    (dotimes (k n (nreverse out))
      (let* ((t01 (if (> n 1) (/ k (- n 1.0)) 0.0))
             (a   (%sample-mod amp    t01))
             (o   (%sample-mod offset t01))
             (ay  (%sample-mod asym   t01))
             (sk  (max -0.999d0 (min 0.999d0 (%sample-mod skew t01))))
             (ph  (mod (+ (* cycles t01) phase) 1.0))
             (d   (+ 0.5d0 (* 0.5d0 sk)))         ; verschiebt den Scheitel
             (uu  (if (< ph d)
                      (* 0.5d0 (/ ph d))
                      (+ 0.5d0 (* 0.5d0 (/ (- ph d) (- 1.0 d))))))
             (s   (sin (* 2 pi uu))))
        ;; vertikale Asymmetrie: positive und negative Halbwelle skalieren
        (setf s (if (>= s 0.0) (* s (+ 1.0 ay)) (* s (- 1.0 ay))))
        (push (+ o (* a s)) out)))))

(defun gen-asym-sine-env (n top bottom &key (freq 5.0) (dur 1.0)
                                            (skew 0.0) (phase 0.0))
  "Bequemer, wenn man die Asymmetrie direkt als zwei Hüllkurven denkt:
   TOP = obere Grenzkurve, BOTTOM = untere Grenzkurve (Zahl, Liste oder
   Funktion). Die Sinuswelle schwingt zwischen BOTTOM und TOP. Verschiedene
   Konturen für TOP und BOTTOM ergeben genau die Asymmetrie der Zeichnung."
  (gen-asym-sine n :freq freq :dur dur :phase phase :skew skew
                 :amp    (lambda (x) (* 0.5 (- (%sample-mod top x)
                                               (%sample-mod bottom x))))
                 :offset (lambda (x) (* 0.5 (+ (%sample-mod top x)
                                               (%sample-mod bottom x))))))

;;; ----------------------------------------------------------------------------
;;;  Beispiele
;;; ----------------------------------------------------------------------------
#|
;; 1) Wie in der Abbildung: 5 Hz, anschwellende Amplitude, driftender Offset,
;;    Wellenberge nach rechts geneigt (skew +0.35).
(list-plot
  (gen-asym-sine 1000 :freq 5
                      :amp    '(0.15 0.4 0.55 0.35 0.2)
                      :offset '(0.3 0.55 0.75 0.6 0.35)
                      :skew   0.35))

;; 2) Direkt über obere/untere Hüllkurve gedacht:
(list-plot
  (gen-asym-sine-env 1000
                     '(0.6 0.9 1.0 0.8 0.5)     ; TOP
                     '(0.1 0.2 0.15 0.3 0.1)    ; BOTTOM
                     :freq 5 :skew -0.3))

;; 3) Als kompositorische Parameterkette (z.B. 48 Werte -> Tonhöhen/Dynamik).
;;    Die Liste geht direkt in vector-to-pitch / vector-to-velocity /
;;    vector-to-length usw.
(setf data (gen-asym-sine 48 :freq 5
                             :amp    '(0.2 0.5 0.3)
                             :offset '(0.4 0.6 0.4)
                             :asym   0.4))     ; Berge höher als Täler
|#
