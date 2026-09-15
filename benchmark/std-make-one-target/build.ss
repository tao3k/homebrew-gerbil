#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; One native std/make target. Keep this fixture independent of the tap and
;;; downstream build frameworks so the receipt measures Gerbil itself.

(import :std/build-script)

(defbuild-script '("probe.ss"))
