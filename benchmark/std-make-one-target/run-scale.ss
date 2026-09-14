;;; -*- Gerbil -*-
;;; Package/macro scale Scenario with one measured aggregate target.

(import :gerbil/runtime/gambit "./benchmark-support")

(def (write-source path writer)
  (call-with-output-file path writer))

(def (write-line port . values)
  (for-each (lambda (value) (display value port)) values)
  (newline port))

(def (package-id index)
  (string-append "pkg" (number->string index)))

(def (leaf-id index)
  (string-append "leaf" (number->string index)))

(def (binding-id package leaf suffix)
  (string-append package "-" leaf "-" suffix))

(def (generate-package source-root package-index modules-per-package)
  (let* ((package (package-id package-index))
         (package-name (string-append "std-make-scale/" package))
         (package-root (path-expand package (path-expand "packages" source-root)))
         (leaves (map leaf-id (iota modules-per-package 1))))
    (create-directory* package-root)
    (write-source (path-expand "gerbil.pkg" package-root)
      (lambda (port)
        (display "(package: " port)
        (display package-name port)
        (write-line port ")")))
    (for-each
     (lambda (leaf index)
       (let ((rule (binding-id package leaf "rule"))
             (value (binding-id package leaf "value")))
         (write-source (path-expand (string-append leaf ".ss") package-root)
           (lambda (port)
             (write-line port "(export " rule " " value ")")
             (write-line port "(defrules " rule " ()")
             (write-line port "  ((_ value)")
             (write-line port "   (list '" package "/" leaf " value)))")
             (write-line port "(def " value " (" rule " " index "))")))))
     leaves (iota modules-per-package 1))
    (write-source (path-expand "interface.ss" package-root)
      (lambda (port)
        (display "(import" port)
        (for-each (lambda (leaf)
                    (display " :" port) (display package-name port)
                    (display "/" port) (display leaf port))
                  leaves)
        (write-line port ")")
        (display "(export" port)
        (for-each (lambda (leaf)
                    (display " (import: :" port) (display package-name port)
                    (display "/" port) (display leaf port) (display ")" port))
                  leaves)
        (write-line port ")")))
    (write-source (path-expand "build.ss" package-root)
      (lambda (port)
        (write-line port "#!/usr/bin/env gxi")
        (write-line port "(import :std/build-script)")
        (display "(defbuild-script '" port)
        (write (append leaves '("interface")) port)
        (write-line port ")")))
    package-root))

(def (generate-app source-root package-count modules-per-package)
  (let* ((app-root (path-expand "app" source-root))
         (packages (map package-id (iota package-count 1))))
    (create-directory* app-root)
    (write-source (path-expand "gerbil.pkg" app-root)
      (lambda (port) (write-line port "(package: std-make-scale/app)")))
    (write-source (path-expand "probe.ss" app-root)
      (lambda (port)
        (display "(import" port)
        (for-each (lambda (package)
                    (display " :std-make-scale/" port)
                    (display package port) (display "/interface" port))
                  packages)
        (write-line port ")")
        (write-line port "(export scale-probe)")
        (display "(def scale-probe (list" port)
        (for-each
         (lambda (package)
           (for-each
            (lambda (index)
              (let (leaf (leaf-id index))
                (display " (" port)
                (display (binding-id package leaf "rule") port)
                (display " " port) (display index port) (display ")" port)))
            (iota modules-per-package 1)))
         packages)
        (write-line port "))")))
    (write-source (path-expand "build-one.ss" app-root)
      (lambda (port)
        (write-line port "#!/usr/bin/env gxi")
        (write-line port "(import :std/build-script)")
        (write-line port "(defbuild-script '(\"probe\"))")))
    app-root))

(def (main . _)
  (let* ((package-count
          (string->number (getenv "SCALE_PACKAGE_COUNT" "8")))
         (modules-per-package
          (string->number (getenv "SCALE_MODULES_PER_PACKAGE" "16")))
         (run-root (benchmark-temporary-root "std-make-package-scale"))
         (source-root (path-expand "source" run-root))
         (image (path-expand "image" run-root))
         (packages-root (path-expand "packages" source-root))
         (receipt-path
          (path-expand "v19-staging-std-make-scale-receipt.ss"
                       (getenv "RUNNER_TEMP" run-root))))
    (create-directory* packages-root)
    (create-directory* image)
    (let* ((package-roots
            (map (lambda (index)
                   (generate-package source-root index modules-per-package))
                 (iota package-count 1)))
           (app-root
            (generate-app source-root package-count modules-per-package))
           (gxi (benchmark-gxi))
           (seed-samples
            (append
             (map (lambda (package-root)
                    (benchmark-measure 'seed-package image package-root
                                       [gxi "./build.ss"]))
                  package-roots)
             (list (benchmark-measure 'seed-app image app-root
                                      [gxi "./build-one.ss"]))))
           (_invalidate
            (call-with-output-file
             (list path: (path-expand "probe.ss" app-root) append: #t)
             (lambda (port) (newline port))))
           (cold (benchmark-measure 'cold image app-root
                                    [gxi "./build-one.ss"]))
           (warm
            (map (lambda (index)
                   (benchmark-measure
                    (string->symbol
                     (string-append "warm" (number->string index)))
                    image app-root [gxi "./build-one.ss"]))
                 (iota 3 1)))
           (warm-p50 (benchmark-warm-p50 warm))
           (warm-compile-count (benchmark-series-compile-count warm))
           (classification (benchmark-classification warm-p50))
           (receipt
            `((schema . homebrew-gerbil.v19-staging.std-make-package-macro-one-target.v2)
              (upstreamRef . ,(getenv "GERBIL_SOURCE_REF" "v0.19-staging"))
              (upstreamSha . ,(getenv "UPSTREAM_SHA" "local"))
              (targetCount . 1)
              (packageCount . ,package-count)
              (macroModuleCount . ,(* package-count modules-per-package))
              (seed . ,seed-samples)
              (cold . ,cold)
              (warm . ,warm)
              (warmP50Ns . ,warm-p50)
              (warmCompileCount . ,warm-compile-count)
              (classification . ,classification))))
      (benchmark-write-receipt receipt-path receipt)
      (displayln "[std-make-scale-benchmark] warm-p50-ns=" warm-p50
                 " warm-compile-count=" warm-compile-count
                 " classification=" classification
                 " receipt=" receipt-path)
      (unless (= (benchmark-sample-ref cold 'compileCount) 1)
        (error "cold aggregate must compile exactly one target" cold))
      (unless (= warm-compile-count 0)
        (error "warm aggregate unexpectedly recompiled" warm))
      (when (eq? classification 'warm-budget-exceeded)
        (error "warm p50 exceeded Scenario budget" warm-p50)))))
