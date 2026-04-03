(clear)
;;; ============================================================
;;;  DIESEL FUEL SYSTEM — Bunker Tank Expert System
;;;  File: diesel_fuel_system.clp   CLIPS 6.4
;;;  ВЕРСИЯ 3.1 — FIRE / MAINTENANCE / NORMAL (FINAL)
;;; ============================================================
;;;
;;;  РЕЖИМЫ РАБОТЫ:
;;;    (set-mode NORMAL)     — обычная работа, авто-остановки активны
;;;    (set-mode FIRE)       — пожар: все насосы останавливаются,
;;;                            команды запуска игнорируются
;;;    (set-mode MAINTENANCE) — техобслуживание: насосы НЕ останавливаются
;;;                            автоматически, запуск возможен из любого
;;;                            состояния (включая STOPPED-AUTO)
;;;
;;;  ОСТАЛЬНЫЕ КОМАНДЫ БЕЗ ИЗМЕНЕНИЙ
;;; ============================================================


;;; ============================================================
;;;  SECTION 1 — GLOBALS
;;; ============================================================

(defglobal
   ?*CAPACITY*      = 20000
   ?*LSHH*          = 18000
   ?*LSH*           = 16000
   ?*LSL*           =  4000
   ?*LSLL*          =  2000
   ?*BUNKER-RATE*   =   600
   ?*TRANSFER-RATE* =   400
   ?*STEP-COUNT*    =     0
)


;;; ============================================================
;;;  SECTION 2 — TEMPLATES
;;; ============================================================

(deftemplate tank
   (slot volume     (type FLOAT)  (default 9000.0))
   (slot level-zone (type SYMBOL)
         (allowed-symbols LSHH LSH NORMAL LSL LSLL)
         (default NORMAL)))

(deftemplate bunker-pump
   (slot state (type SYMBOL)
         (allowed-symbols READY RUNNING STOPPED-AUTO STOPPED-MANUAL)
         (default READY)))

(deftemplate transfer-pump
   (slot state (type SYMBOL)
         (allowed-symbols READY RUNNING STOPPED-AUTO STOPPED-MANUAL)
         (default READY)))

(deftemplate alarm
   (slot kind   (type SYMBOL)
         (allowed-symbols VISUAL SOUND MESSAGE))
   (slot active (type SYMBOL)
         (allowed-symbols TRUE FALSE)
         (default FALSE))
   (slot text   (type STRING) (default "")))

(deftemplate event-log
   (slot step        (type INTEGER) (default 0))
   (slot description (type STRING)))

(deftemplate sequence-flag
   (slot name  (type SYMBOL))
   (slot value (type SYMBOL)
         (allowed-symbols TRUE FALSE)
         (default FALSE)))

(deftemplate mode
   (slot current (type SYMBOL)
         (allowed-symbols NORMAL FIRE MAINTENANCE)
         (default NORMAL)))


;;; ============================================================
;;;  SECTION 3 — INITIAL STATE
;;; ============================================================

(deffacts initial-state
   (tank          (volume 9000.0) (level-zone NORMAL))
   (bunker-pump   (state READY))
   (transfer-pump (state READY))
   (alarm         (kind VISUAL)  (active FALSE) (text ""))
   (alarm         (kind SOUND)   (active FALSE) (text ""))
   (alarm         (kind MESSAGE) (active FALSE) (text ""))
   (sequence-flag (name lshh-occurred) (value FALSE))
   (sequence-flag (name lsh-occurred)  (value FALSE))
   (sequence-flag (name lsl-occurred)  (value FALSE))
   (sequence-flag (name lsll-occurred) (value FALSE))
   (mode (current NORMAL)))


;;; ============================================================
;;;  SECTION 4 — ZONE CLASSIFICATION
;;; ============================================================

(defrule classify-lshh
   (declare (salience 90))
   ?t <- (tank (volume ?v) (level-zone ?z&~LSHH))
   (test (>= ?v (float ?*LSHH*)))
   => (modify ?t (level-zone LSHH)))

(defrule classify-lsh
   (declare (salience 90))
   ?t <- (tank (volume ?v) (level-zone ?z&~LSH))
   (test (and (>= ?v (float ?*LSH*)) (< ?v (float ?*LSHH*))))
   => (modify ?t (level-zone LSH)))

(defrule classify-normal
   (declare (salience 90))
   ?t <- (tank (volume ?v) (level-zone ?z&~NORMAL))
   (test (and (> ?v (float ?*LSL*)) (< ?v (float ?*LSH*))))
   => (modify ?t (level-zone NORMAL)))

(defrule classify-lsl
   (declare (salience 90))
   ?t <- (tank (volume ?v) (level-zone ?z&~LSL))
   (test (and (> ?v (float ?*LSLL*)) (<= ?v (float ?*LSL*))))
   => (modify ?t (level-zone LSL)))

(defrule classify-lsll
   (declare (salience 90))
   ?t <- (tank (volume ?v) (level-zone ?z&~LSLL))
   (test (<= ?v (float ?*LSLL*)))
   => (modify ?t (level-zone LSLL)))


;;; ============================================================
;;;  SECTION 5 — SETPOINT RESPONSE RULES
;;;  (Автоостановка — ТОЛЬКО в режиме NORMAL, без флагов)
;;; ============================================================

;;; --- LSHH : остановить bunker pump в NORMAL ---
(defrule respond-lshh-stop-bunker
   (declare (salience 70))
   (mode (current NORMAL))
   (tank (level-zone LSHH))
   ?bp <- (bunker-pump (state RUNNING))
   =>
   (retract ?bp)
   (assert (bunker-pump (state STOPPED-AUTO)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSHH: Bunker pump auto-stopped (NORMAL mode)."))))

;;; В MAINTENANCE — только логируем, не останавливаем
(defrule respond-lshh-maintenance-log
   (declare (salience 69))
   (mode (current MAINTENANCE))
   (tank (level-zone LSHH))
   (bunker-pump (state RUNNING))
   (not (event-log (description ~"MAINTENANCE: LSHH ignored*")))
   =>
   (assert (event-log (step ?*STEP-COUNT*)
      (description "MAINTENANCE: LSHH ignored — pump continues."))))

;;; --- LSLL : остановить transfer pump в NORMAL ---
(defrule respond-lsll-stop-transfer
   (declare (salience 70))
   (mode (current NORMAL))
   (tank (level-zone LSLL))
   ?tp <- (transfer-pump (state RUNNING))
   =>
   (retract ?tp)
   (assert (transfer-pump (state STOPPED-AUTO)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSLL: Transfer pump auto-stopped (NORMAL mode)."))))

(defrule respond-lsll-maintenance-log
   (declare (salience 69))
   (mode (current MAINTENANCE))
   (tank (level-zone LSLL))
   (transfer-pump (state RUNNING))
   (not (event-log (description ~"MAINTENANCE: LSLL ignored*")))
   =>
   (assert (event-log (step ?*STEP-COUNT*)
      (description "MAINTENANCE: LSLL ignored — pump continues."))))


;;; ============================================================
;;;  SECTION 6 — ALARM RULES (всегда активны, без изменений)
;;; ============================================================

(defrule alarm-lshh-visual
   (declare (salience 65))
   (tank (level-zone LSHH))
   ?a <- (alarm (kind VISUAL))
   =>
   (modify ?a (active TRUE) (text "CRITICAL HIGH — LSHH")))

(defrule alarm-lshh-sound
   (declare (salience 65))
   (tank (level-zone LSHH))
   ?a <- (alarm (kind SOUND))
   =>
   (modify ?a (active TRUE) (text "CRITICAL HIGH — LSHH")))

(defrule alarm-lshh-message
   (declare (salience 65))
   (tank (level-zone LSHH))
   ?a <- (alarm (kind MESSAGE))
   =>
   (modify ?a (active TRUE)
         (text "Tank critically high. Bunker pump stopped. Check overflow risk.")))

(defrule alarm-lsh-visual
   (declare (salience 65))
   (tank (level-zone LSH))
   ?a <- (alarm (kind VISUAL))
   =>
   (modify ?a (active TRUE) (text "HIGH LEVEL — LSH")))

(defrule alarm-lsh-sound
   (declare (salience 65))
   (tank (level-zone LSH))
   ?a <- (alarm (kind SOUND))
   =>
   (modify ?a (active TRUE) (text "HIGH LEVEL — LSH")))

(defrule alarm-lsh-message
   (declare (salience 65))
   (tank (level-zone LSH))
   ?a <- (alarm (kind MESSAGE))
   =>
   (modify ?a (active TRUE)
         (text "Tank level high. Consider stopping bunker pump.")))

(defrule alarm-lsl-visual
   (declare (salience 65))
   (tank (level-zone LSL))
   ?a <- (alarm (kind VISUAL))
   =>
   (modify ?a (active TRUE) (text "LOW LEVEL — LSL")))

(defrule alarm-lsl-message
   (declare (salience 65))
   (tank (level-zone LSL))
   ?a <- (alarm (kind MESSAGE))
   =>
   (modify ?a (active TRUE)
         (text "Tank level low. Start bunker pump to receive fuel.")))

(defrule alarm-lsll-visual
   (declare (salience 65))
   (tank (level-zone LSLL))
   ?a <- (alarm (kind VISUAL))
   =>
   (modify ?a (active TRUE) (text "CRITICAL LOW — LSLL")))

(defrule alarm-lsll-message
   (declare (salience 65))
   (tank (level-zone LSLL))
   ?a <- (alarm (kind MESSAGE))
   =>
   (modify ?a (active TRUE)
         (text "Tank critically low. Transfer pump stopped. Dry-run risk. Start bunker pump.")))


;;; ============================================================
;;;  SECTION 7 — SEQUENCE FLAGS (для sequence-правил)
;;; ============================================================

(defrule respond-lsh-flag
   (declare (salience 70))
   (tank (level-zone LSH))
   ?sf <- (sequence-flag (name lsh-occurred) (value FALSE))
   =>
   (modify ?sf (value TRUE))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSH: High level warning."))))

(defrule respond-lsl-flag
   (declare (salience 70))
   (tank (level-zone LSL))
   ?sf <- (sequence-flag (name lsl-occurred) (value FALSE))
   =>
   (modify ?sf (value TRUE))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSL: Low level warning."))))

;;; Флаги LSHH и LSLL устанавливаются, но не используются для остановки
(defrule respond-lshh-flag
   (declare (salience 70))
   (tank (level-zone LSHH))
   ?sf <- (sequence-flag (name lshh-occurred) (value FALSE))
   =>
   (modify ?sf (value TRUE))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSHH: Critical high level reached."))))

(defrule respond-lsll-flag
   (declare (salience 70))
   (tank (level-zone LSLL))
   ?sf <- (sequence-flag (name lsll-occurred) (value FALSE))
   =>
   (modify ?sf (value TRUE))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "LSLL: Critical low level reached."))))


;;; ============================================================
;;;  SECTION 8 — SEQUENCE RULES & INTERLOCKS
;;; ============================================================

(defrule sequence-lsll-then-lsh
   (declare (salience 60))
   (tank (level-zone LSH))
   (sequence-flag (name lsll-occurred) (value TRUE))
   (not (event-log (description "SEQ: Rapid fill — LSLL then LSH.")))
   =>
   (assert (event-log (step ?*STEP-COUNT*)
      (description "SEQ: Rapid fill — LSLL then LSH.")))
   (do-for-fact ((?a alarm)) (eq ?a:kind MESSAGE)
      (modify ?a (active TRUE)
         (text "SEQ ALERT: Rapid fill — tank rose from LSLL to LSH. Verify inlet valve. Overfill risk."))))

(defrule sequence-lshh-then-lsll
   (declare (salience 60))
   (tank (level-zone LSLL))
   (sequence-flag (name lshh-occurred) (value TRUE))
   (not (event-log (description "SEQ: Full drain after LSHH trip.")))
   =>
   (assert (event-log (step ?*STEP-COUNT*)
      (description "SEQ: Full drain after LSHH trip.")))
   (do-for-fact ((?a alarm)) (eq ?a:kind MESSAGE)
      (modify ?a (active TRUE)
         (text "SEQ ALERT: Tank drained to LSLL after LSHH trip. Possible leak. Inspect immediately."))))

(defrule interlock-bunker-restart-after-lshh
   (declare (salience 80))
   (mode (current NORMAL))
   (tank (level-zone ?z&:(or (eq ?z LSHH) (eq ?z LSH))))
   (sequence-flag (name lshh-occurred) (value TRUE))
   ?bp <- (bunker-pump (state READY))
   (not (event-log (description "SEQ: Bunker pump restart blocked — LSHH not cleared.")))
   =>
   (retract ?bp)
   (assert (bunker-pump (state STOPPED-AUTO)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "SEQ: Bunker pump restart blocked — LSHH not cleared.")))
   (do-for-fact ((?a alarm)) (eq ?a:kind MESSAGE)
      (modify ?a (active TRUE)
         (text "INTERLOCK: Bunker pump blocked. LSHH not cleared. Return to NORMAL first."))))


;;; ============================================================
;;;  SECTION 9 — FIRE MODE RULES
;;; ============================================================

(defrule fire-mode-stop-all-pumps
   (declare (salience 100))
   (mode (current FIRE))
   ?bp <- (bunker-pump (state RUNNING))
   =>
   (retract ?bp)
   (assert (bunker-pump (state STOPPED-AUTO)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "FIRE MODE: Bunker pump forced STOP."))))

(defrule fire-mode-stop-transfer-pump
   (declare (salience 100))
   (mode (current FIRE))
   ?tp <- (transfer-pump (state RUNNING))
   =>
   (retract ?tp)
   (assert (transfer-pump (state STOPPED-AUTO)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "FIRE MODE: Transfer pump forced STOP."))))

(defrule fire-alarm-message
   (declare (salience 95))
   (mode (current FIRE))
   (not (event-log (description "FIRE MODE activated*")))
   =>
   (assert (event-log (step ?*STEP-COUNT*)
      (description "FIRE MODE activated — all pumps stopped, starts blocked.")))
   (do-for-fact ((?a alarm)) (eq ?a:kind MESSAGE)
      (modify ?a (active TRUE)
         (text "FIRE MODE ACTIVE! All pumps stopped. Emergency procedure."))))


;;; ============================================================
;;;  SECTION 10 — CLEAR ALARMS ON NORMAL
;;; ============================================================

(defrule clear-alarms-on-normal
   (declare (salience 50))
   (tank (level-zone NORMAL))
   (mode (current NORMAL))
   ?a <- (alarm (active TRUE))
   => (modify ?a (active FALSE) (text "")))


;;; ============================================================
;;;  SECTION 11 — GETTER FUNCTIONS
;;; ============================================================

(deffunction get-tank-volume ()
   (bind ?v 0.0)
   (do-for-fact ((?t tank)) TRUE (bind ?v ?t:volume))
   ?v)

(deffunction get-tank-zone ()
   (bind ?z NORMAL)
   (do-for-fact ((?t tank)) TRUE (bind ?z ?t:level-zone))
   ?z)

(deffunction get-bunker-state ()
   (bind ?s READY)
   (do-for-fact ((?bp bunker-pump)) TRUE (bind ?s ?bp:state))
   ?s)

(deffunction get-transfer-state ()
   (bind ?s READY)
   (do-for-fact ((?tp transfer-pump)) TRUE (bind ?s ?tp:state))
   ?s)

(deffunction get-mode ()
   (bind ?m NORMAL)
   (do-for-fact ((?md mode)) TRUE (bind ?m ?md:current))
   ?m)


;;; ============================================================
;;;  SECTION 12 — SIMULATION FUNCTIONS
;;; ============================================================

(deffunction do-step ()
   (bind ?*STEP-COUNT* (+ ?*STEP-COUNT* 1))
   (bind ?vol   (get-tank-volume))
   (bind ?bp-st (get-bunker-state))
   (bind ?tp-st (get-transfer-state))
   (bind ?delta 0.0)
   (if (eq ?bp-st RUNNING)
      then (bind ?delta (+ ?delta (float ?*BUNKER-RATE*))))
   (if (eq ?tp-st RUNNING)
      then (bind ?delta (- ?delta (float ?*TRANSFER-RATE*))))
   (bind ?new-vol
      (max 0.0 (min (float ?*CAPACITY*) (+ ?vol ?delta))))
   (do-for-fact ((?t tank)) TRUE
      (modify ?t (volume ?new-vol)))
   (run))

(deffunction fmt-alarm (?kind)
   (do-for-fact ((?a alarm)) (eq ?a:kind ?kind)
      (if (eq ?a:active TRUE)
         then (printout t "  " ?kind " : *** LIVE *** " ?a:text crlf)
         else (printout t "  " ?kind " : None" crlf))))

(deffunction status ()
   (bind ?vol   (get-tank-volume))
   (bind ?zone  (get-tank-zone))
   (bind ?bp-st (get-bunker-state))
   (bind ?tp-st (get-transfer-state))
   (bind ?mode  (get-mode))
   (printout t crlf)
   (printout t "============================================" crlf)
   (printout t "  BUNKER TANK — STATUS  [step " ?*STEP-COUNT* "]" crlf)
   (printout t "============================================" crlf)
   (printout t "  OPERATION MODE : " ?mode crlf)
   (printout t "--------------------------------------------" crlf)
   (printout t "  SETPOINTS (L)" crlf)
   (printout t "  LSHH " ?*LSHH*
               " | LSH "  ?*LSH*
               " | LSL "  ?*LSL*
               " | LSLL " ?*LSLL*
               " | Max "  ?*CAPACITY* crlf)
   (printout t "--------------------------------------------" crlf)
   (printout t "  TANK" crlf)
   (printout t "  Volume     : " (integer ?vol)
               " L  /  " ?*CAPACITY* " L" crlf)
   (printout t "  Level zone : " ?zone crlf)
   (printout t "--------------------------------------------" crlf)
   (printout t "  PUMPS" crlf)
   (printout t "  Bunker   : " ?bp-st
               "  (+" ?*BUNKER-RATE* " L/step — fills tank)" crlf)
   (printout t "  Transfer : " ?tp-st
               "  (-" ?*TRANSFER-RATE* " L/step — empties tank)" crlf)
   (printout t "--------------------------------------------" crlf)
   (printout t "  ALARMS" crlf)
   (fmt-alarm VISUAL)
   (fmt-alarm SOUND)
   (fmt-alarm MESSAGE)
   (printout t "--------------------------------------------" crlf)
   (printout t "  COMMANDS" crlf)
   (printout t "  (start-bunker-pump)    (stop-bunker-pump)" crlf)
   (printout t "  (start-transfer-pump)  (stop-transfer-pump)" crlf)
   (printout t "  (step)                 (step-n <n>)" crlf)
   (printout t "  (set-volume <litres>)  (history)" crlf)
   (printout t "  (status)               (reset-system)" crlf)
   (printout t "  (set-mode NORMAL)      (set-mode FIRE)   (set-mode MAINTENANCE)" crlf)
   (printout t "============================================" crlf crlf))

;;; ============================================================
;;;  START / STOP FUNCTIONS
;;; ============================================================

(deffunction start-bunker-pump ()
   (bind ?mode (get-mode))
   (if (eq ?mode FIRE)
      then
         (printout t "  FIRE MODE: Cannot start bunker pump." crlf)
         (return))
   (bind ?vol   (get-tank-volume))
   (bind ?bp-st (get-bunker-state))
   ;; В режиме MAINTENANCE разрешаем запуск из любого состояния, кроме RUNNING
   (if (eq ?mode MAINTENANCE)
      then
         (if (eq ?bp-st RUNNING)
            then (printout t "  Pump already RUNNING." crlf)
            else
               (do-for-fact ((?bp bunker-pump)) TRUE (retract ?bp))
               (assert (bunker-pump (state RUNNING)))
               (assert (event-log (step ?*STEP-COUNT*)
                  (description "Operator: Bunker pump started (MAINTENANCE override).")))
               (printout t "  Bunker pump RUNNING. (+" ?*BUNKER-RATE* " L/step)" crlf)
               (printout t "  (MAINTENANCE mode: override active)" crlf))
         (return))
   ;; Режим NORMAL: обычная логика с блокировкой по LSHH
   (if (>= ?vol (float ?*LSHH*))
      then
         (printout t "  BLOCKED: Tank at LSHH (" (integer ?vol) " L). Overflow risk." crlf)
   else (if (or (eq ?bp-st READY) (eq ?bp-st STOPPED-MANUAL))
      then
         (do-for-fact ((?bp bunker-pump)) TRUE (retract ?bp))
         (assert (bunker-pump (state RUNNING)))
         (assert (event-log (step ?*STEP-COUNT*)
            (description "Operator: Bunker pump started.")))
         (printout t "  Bunker pump RUNNING. (+" ?*BUNKER-RATE* " L/step)" crlf)
      else
         (printout t "  Cannot start — state: " ?bp-st crlf))))

(deffunction stop-bunker-pump ()
   (do-for-fact ((?bp bunker-pump)) TRUE (retract ?bp))
   (assert (bunker-pump (state STOPPED-MANUAL)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "Operator: Bunker pump stopped manually.")))
   (printout t "  Bunker pump STOPPED (manual)." crlf))

(deffunction start-transfer-pump ()
   (bind ?mode (get-mode))
   (if (eq ?mode FIRE)
      then
         (printout t "  FIRE MODE: Cannot start transfer pump." crlf)
         (return))
   (bind ?vol   (get-tank-volume))
   (bind ?tp-st (get-transfer-state))
   ;; В режиме MAINTENANCE разрешаем запуск из любого состояния, кроме RUNNING
   (if (eq ?mode MAINTENANCE)
      then
         (if (eq ?tp-st RUNNING)
            then (printout t "  Pump already RUNNING." crlf)
            else
               (do-for-fact ((?tp transfer-pump)) TRUE (retract ?tp))
               (assert (transfer-pump (state RUNNING)))
               (assert (event-log (step ?*STEP-COUNT*)
                  (description "Operator: Transfer pump started (MAINTENANCE override).")))
               (printout t "  Transfer pump RUNNING. (-" ?*TRANSFER-RATE* " L/step)" crlf)
               (printout t "  (MAINTENANCE mode: override active)" crlf))
         (return))
   ;; Режим NORMAL: обычная логика с блокировкой по LSLL
   (if (<= ?vol (float ?*LSLL*))
      then
         (printout t "  BLOCKED: Tank at LSLL (" (integer ?vol) " L). Dry-run risk." crlf)
   else (if (or (eq ?tp-st READY) (eq ?tp-st STOPPED-MANUAL))
      then
         (do-for-fact ((?tp transfer-pump)) TRUE (retract ?tp))
         (assert (transfer-pump (state RUNNING)))
         (assert (event-log (step ?*STEP-COUNT*)
            (description "Operator: Transfer pump started.")))
         (printout t "  Transfer pump RUNNING. (-" ?*TRANSFER-RATE* " L/step)" crlf)
      else
         (printout t "  Cannot start — state: " ?tp-st crlf))))

(deffunction stop-transfer-pump ()
   (do-for-fact ((?tp transfer-pump)) TRUE (retract ?tp))
   (assert (transfer-pump (state STOPPED-MANUAL)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description "Operator: Transfer pump stopped manually.")))
   (printout t "  Transfer pump STOPPED (manual)." crlf))

(deffunction step ()
   (do-step)
   (status))

(deffunction step-n (?n)
   (loop-for-count (?i 1 ?n) (do-step))
   (status))

(deffunction set-volume (?v)
   (bind ?v (max 0.0 (min (float ?*CAPACITY*) (float ?v))))
   (do-for-fact ((?t tank)) TRUE (modify ?t (volume ?v)))
   (assert (event-log (step ?*STEP-COUNT*)
      (description (str-cat "Manual: Volume set to " (integer ?v) " L."))))
   (run)
   (status))

(deffunction history ()
   (printout t crlf "  EVENT HISTORY" crlf)
   (printout t "  ----------------------------------------" crlf)
   (do-for-all-facts ((?e event-log)) TRUE
      (printout t "  [step " ?e:step "] " ?e:description crlf))
   (printout t crlf))

(deffunction set-mode (?new-mode)
   (bind ?new-mode (upcase ?new-mode))
   (if (or (eq ?new-mode NORMAL) (eq ?new-mode FIRE) (eq ?new-mode MAINTENANCE))
      then
         (do-for-fact ((?md mode)) TRUE
            (modify ?md (current ?new-mode)))
         ;; При переходе в NORMAL сбрасываем флаги LSHH и LSLL,
         ;; чтобы sequence-правила могли сработать заново.
         (if (eq ?new-mode NORMAL)
            then
               (do-for-fact ((?sf sequence-flag))
                  (or (eq ?sf:name lshh-occurred) (eq ?sf:name lsll-occurred))
                  (modify ?sf (value FALSE))))
         (assert (event-log (step ?*STEP-COUNT*)
            (description (str-cat "Mode changed to " ?new-mode))))
         (printout t "  Mode set to " ?new-mode crlf)
         (run)
         (status)
      else
         (printout t "  Invalid mode. Use NORMAL, FIRE, or MAINTENANCE." crlf)))

(deffunction reset-system ()
   (bind ?*STEP-COUNT* 0)
   (reset)
   (run)
   (status))


;;; ============================================================
;;;  SECTION 13 — STARTUP & AUTO-INIT
;;; ============================================================

(defrule startup
   (declare (salience -200))
   (initial-fact)
   =>
   (status))

(reset)
(run)