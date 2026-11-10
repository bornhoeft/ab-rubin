;;; ============================================================
;;; Arithmetische Streckenteilung mit garantiert exakter Summe
;;; ============================================================
;;;
;;; Problem: (mapcar #'round (scale-to-sum total liste)) rundet
;;; jeden Wert einzeln - dadurch kann die Summe der gerundeten
;;; Werte um 1-2 Einheiten von TOTAL abweichen.
;;;
;;; Lösung: round-preserve-sum verwendet die "Methode der größten
;;; Reste" (Hamilton-Verfahren, auch in der Sitzverteilung bei
;;; Wahlen verwendet): erst abrunden, dann die fehlende Differenz
;;; an die Werte mit den größten Nachkommaresten verteilen.
;;; Ergebnis: die Summe stimmt IMMER exakt.

(defun round-preserve-sum (values total)
  "Rundet VALUES (reelle/rationale Zahlen) auf Ganzzahlen, so dass
   die Summe exakt TOTAL ergibt."
  (let* ((total (round total))
         (floors (mapcar #'floor values))
         (rests  (mapcar #'- values floors))
         (deficit (round (- total (reduce #'+ floors))))
         (order (sort 
                 (loop for r in rests for i from 0 
                       collect (cons i r))
                       #'> :key #'cdr))
         (bump-idx (mapcar #'car
                            (subseq order 0 
                                    (max 0 
                                         (min deficit 
                                              (length order)))))))
    (loop for f in floors
          for i from 0
          collect (if (member i bump-idx) (1+ f) f))))

;;; ------------------------------------------------------------
;;; Arithmetische Reihe mit N Gliedern von START bis END
;;; ------------------------------------------------------------

(defun gen-arithmetic-series (n &key (start 1) (end n))
  "Erzeugt eine arithmetische Reihe mit N Gliedern 
von START bis END."
  (if (= n 1)
      (list start)
      (let ((step (/ (- end start) (1- n))))
        (loop for i from 0 below n collect (+ start (* i step))))))

;;; ------------------------------------------------------------
;;; Hauptfunktion: TOTAL in N arithmetisch gestaffelte Teile
;;; ------------------------------------------------------------

(defun partition-arithmetic (total n &key (start 1) (end n))
  "Teilt TOTAL in N Teilstrecken, deren Größen einer arithmetischen
   Reihe von START bis END folgen (Standard: 1,2,...,N, also linear
   ansteigend), proportional skaliert. Die Summe der Teile ergibt
   garantiert exakt TOTAL.

   START/END bestimmen nur die FORM der Reihe (das Verhältnis
   zwischen erstem und letztem Glied), nicht die tatsächlichen
   Endwerte - diese ergeben sich erst durch die Skalierung auf 
   TOTAL.
   START > END erzeugt automatisch eine absteigende Reihe.

   Beispiele:
   (partition-arithmetic 100 4) => (10 20 30 40)
   (partition-arithmetic 100 4 :start 4 :end 1) => (40 30 20 10)
   (partition-arithmetic 100 6) => (5 9 14 19 24 29)"
  (let* ((series (gen-arithmetic-series n :start start :end end))
         (raw-sum (reduce #'+ series))
         (scaled (mapcar (lambda (x) (* x (/ total raw-sum))) 
                         series)))
    (round-preserve-sum scaled total)))

#|  ------------------------------------------------------------
;;; Drop-in-Ersatz für den ursprünglichen Ansatz mit gen-transition
;;; und scale-to-sum (Opusmodus) - für beliebige Kurvenformen
;;; (exponentielle Übergänge etc.), aber mit exakter Summe:
;;; ------------------------------------------------------------

statt:
 (mapcar #'round 
    (scale-to-sum 100 (gen-transition 5 40 5 1)))
 jetzt:
  (round-preserve-sum (scale-to-sum 100 (gen-transition 5 40 5 1)) 100)
|#
