;;; -*- Gerbil -*-
;;; std/interface supplies a stable, nontrivial precompiled import closure.

(import :std/interface)
(export std-make-one-target-probe)

(def (std-make-one-target-probe)
  'ready)
