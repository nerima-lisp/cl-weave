(in-package #:cl-weave/cli)

(defparameter *installed-source-root* nil
  "Overrides the ASDF source tree IMAGE-ENTRY-POINT registers at startup.
NIL means work it out from where the running image sits, which is what keeps a
delivered binary relocatable. A packager whose layout the discovery in
INSTALLED-SOURCE-ROOT cannot express can set this before the image is dumped.")

(defun anchor-prefix-pathname (anchor)
  "The installation prefix ANCHOR sits under: the parent of its directory, so
that $prefix/bin/cl-weave and $prefix/lib/cl-weave.core both yield $prefix/."
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname anchor)))

(defun image-anchor-pathnames ()
  "The files this image is running out of, most specific first, or NIL on an
implementation with no notion of a dumped-image runtime/core pair distinct
from the compiler that read this file -- i.e. every non-SBCL implementation
cl-weave supports. INSTALLED-SOURCE-ROOT already treats an empty list here
the same as \"nothing found\" and falls through to the ASDF-source-directory
heuristic below it, so returning NIL degrades this to that heuristic rather
than to a load-time error.

SB-EXT:*RUNTIME-PATHNAME* is the executable itself when the image was dumped
with :EXECUTABLE T, and the SBCL binary when the image is a bare core started
with --core; SB-EXT:*CORE-PATHNAME* names the core in that second shape. SBCL
resolves both to an absolute pathname at startup, even when the command was
found on PATH, and both follow the file if it is moved -- which is what makes
a root derived from them survive relocation.

Guarded #+sbcl/#-sbcl (rather than left bare) because SB-EXT is an SBCL-only
package: on any implementation without it, even a form that never runs still
has to be READ, and the reader resolves package-qualified symbols eagerly --
so an unguarded reference here would fail ECL's load of this file with
\"There is no package with the name SB-EXT\" before cl-cli's ECL portable-core
gate could get anywhere near running a test."
  #+sbcl
  (remove-duplicates (remove nil (list sb-ext:*runtime-pathname*
                                       sb-ext:*core-pathname*))
                     :test #'equal)
  #-sbcl
  nil)

(defun installed-source-root ()
  "The ASDF source tree installed alongside this image, or NIL when there is
none to find."
  (or *installed-source-root*
      ;; share/common-lisp/source/ under the installation prefix is where
      ;; every nerima-lisp package puts its sources, so the binary and the
      ;; sources it ships are siblings and neither has to record the other's
      ;; absolute path.
      (loop for anchor in (image-anchor-pathnames)
            thereis (uiop:directory-exists-p
                     (merge-pathnames #p"share/common-lisp/source/"
                                      (anchor-prefix-pathname anchor))))
      ;; Last resort: where ASDF found cl-weave.asd while this image was being
      ;; built. Nothing injected it -- ASDF recorded it as a side effect of
      ;; loading the system -- but it is a build-time absolute path, so it is
      ;; only right while the sources stay where they were compiled. It is
      ;; what lets a core delivered apart from its sources still resolve them.
      (ignore-errors (asdf:system-source-directory "cl-weave"))))

(defun image-entry-point ()
  "Toplevel of the delivered `cl-weave` executable, named by :ENTRY-POINT in
cl-weave.asd.

A dumped image comes back with the global state it was dumped with, which for
a packaged build is a build sandbox that no longer exists. Everything here
puts the process back in touch with the machine it is actually running on
before the CLI sees an argument. It has to work on both delivery shapes -- an
:EXECUTABLE T image, whose toplevel is this function directly, and a bare core
started with --core -- so it may not assume UIOP:RESTORE-IMAGE ran first and
already called the universal restore hooks."
  ;; Read before the registry is replaced: the fallback in
  ;; INSTALLED-SOURCE-ROOT asks ASDF where it found cl-weave.asd.
  (let ((root (installed-source-root)))
    ;; Every relative pathname the user types -- --output, --load, a snapshot
    ;; directory -- is relative to the directory they typed it in.
    (setf *default-pathname-defaults* (uiop:getcwd))
    ;; UIOP caches the temporary directory, so an image carries the builder's
    ;; TMPDIR until this re-reads the environment.
    (uiop:setup-temporary-directory)
    ;; ASDF's configuration is frozen at dump time too. Re-reading it honours
    ;; the caller's CL_SOURCE_REGISTRY, and ROOT puts the sources shipped with
    ;; this image back on the registry, which is what lets
    ;; `cl-weave run cl-weave/test` resolve from outside a checkout.
    (asdf:initialize-source-registry
     (if root
         `(:source-registry (:tree ,root) :inherit-configuration)
         '(:source-registry :inherit-configuration)))
    ;; --coverage recompiles the system under test, and the sources shipped
    ;; with this image are read-only, so FASLs have to land in a writable
    ;; per-user cache no matter what the surrounding environment asks for.
    (asdf:initialize-output-translations
     '(:output-translations (t (:home ".cache" "common-lisp" :implementation))
       :ignore-inherited-configuration))
    (main)))
