;;; py-playground.el --- Local python playground for short snippets.

;; Copyright (C) 2018 Amos Bird
;;   ___                       ______ _         _
;;  / _ \                      | ___ (_)       | |
;; / /_\ \_ __ ___   ___  ___  | |_/ /_ _ __ __| |
;; |  _  | '_ ` _ \ / _ \/ __| | ___ \ | '__/ _` |
;; | | | | | | | | | (_) \__ \ | |_/ / | | | (_| |
;; \_| |_/_| |_| |_|\___/|___/ \____/|_|_|  \__,_|

;; Author: Amos Bird <amosbird@gmail.com>
;; URL: https://github.com/amosbird/python-playground
;; Keywords: tools, python
;; Version: 1.0
;; Package-Requires: ((emacs "25"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Local playground for python programs.
;; `M-x python-playground` and type you code then make&run it with `C-Return`.

;;

;;; Code:

(require 'compile)
(require 'time-stamp)

(defgroup py-playground nil
  "Options specific to python Playground."
  :group 'python)

(defcustom py-playground-ask-file-name nil
  "Non-nil means we ask for a name for the snippet.

By default it will be created as snippet.cpp"
  :type 'boolean
  :group 'py-playground)

(defcustom py-playground-confirm-deletion t
  "Non-nil prompts confirmation on the snippet deletion with `py-playground-rm'.

By default confirmation required."
  :type 'boolean
  :group 'py-playground)

(defcustom py-playground-basedir "~/py-playground"
  "Base directory for playground snippets."
  :type 'file
  :group 'py-playground)

(defcustom py-template "
if __name__ == \"__main__\":"
  "Default template for playground."
  :type 'string
  :group 'py-playground)

(defcustom py-playground-hook nil
  "Hook when entering playground."
  :type 'hook
  :group 'py-playground)

(defcustom py-playground-rm-hook nil
  "Hook when leaving playground."
  :type 'hook
  :group 'py-playground)

(defvar py-debug-command "fish -c 'tmuxpudb ./snippet.py'")

(define-minor-mode py-playground-mode
  "A place for playing with c++ code."
  :init-value nil
  :lighter "Play(Python)"
  :keymap '(([C-return] . py-playground-exec)
            ([S-return] . py-playground-rm)))

(defun py-playground-snippet-file-name(&optional snippet-name)
  "Get snippet file name from SNIPPET-NAME. Generate a random one if nil."
  (let ((file-name (cond (snippet-name)
                         (py-playground-ask-file-name
                          (read-string "Python Playground filename: "))
                         ("snippet"))))
    (concat (py-playground-snippet-unique-dir file-name) "/" file-name ".py")))

(defun py-playground-run (comm)
  "COMM."
  (if (py-playground-inside)
      (progn
        (save-buffer t)
        (make-local-variable 'compile-command)
        (pcase comm
          ('exec
           (compile "python snippet.py"))
          ('debug
           (compile py-debug-command))))))

(defun py-playground-exec ()
  "Save the buffer then run clang compiler for executing the code."
  (interactive)
  (py-playground-run 'exec))

(defun py-playground-debug ()
  "Save the buffer then run pudb for debugging the code."
  (interactive)
  (py-playground-run 'debug))

(defun py-playground-add-or-modify-tag (name)
  "Adding or modifying existing tag of a snippet using NAME."
  (interactive "MTag Name: ")
  (if (py-playground-inside)
      (let* ((oname (string-trim-right (shell-command-to-string (concat "basename " default-directory))))
             (nn (concat default-directory "../"))
             (l (split-string oname "--")))
        (fundamental-mode) ;; weird bug when renaming directory
        (if (= (length l) 1)
            (dired-rename-file default-directory (concat nn name "--" oname) nil)
          (dired-rename-file default-directory (concat nn name "--" (cadr l)) nil)))))

;;;###autoload
(defun py-playground-find-snippet ()
  "List all snippets using `ivy-read'."
  (interactive)
  (ivy-read "Browse py snippet: "
            (mapcar (lambda (a) (cons (file-name-nondirectory (car a)) (car a)))
                    (sort
                     (directory-files-and-attributes py-playground-basedir t "^[^.]" 'nosort)
                     #'(lambda (x y) (time-less-p (nth 6 y) (nth 6 x)))))
            :action (lambda (c) (find-file (concat (cdr c) "/snippet.py")))))

(defun py-playground-copy ()
  "Copy a playground to a newly generated folder."
  (interactive)
  (if (py-playground-inside)
      (let* ((snippet-file-name (py-playground-snippet-file-name))
             (dst-dir (file-name-directory snippet-file-name))
             (snippet "snippet.py")
             (dirlocal ".dir-locals.el")
             (envrc ".envrc"))
        (copy-file snippet dst-dir)
        (copy-file envrc dst-dir)
        (copy-file dirlocal dst-dir)
        (find-file snippet-file-name)
        (run-hooks 'py-playground-hook))))

(defconst py-playground--loaddir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory that py-playground was loaded from.")

;;;###autoload
(defun py-playground ()
  "Run playground for Python language in a new buffer."
  (interactive)
  (let ((snippet-file-name (py-playground-snippet-file-name)))
    (let* ((dir-name (concat py-playground--loaddir "templates/"))
           (dst-dir (file-name-directory snippet-file-name))
           (envrc (concat dir-name ".envrc"))
           (dirlocal (concat dir-name ".dir-locals.el"))
           (snippet (concat dir-name "snippet.py")))
      (copy-file envrc dst-dir)
      (copy-file dirlocal dst-dir)
      (copy-file snippet dst-dir)
      (find-file snippet-file-name)
      (forward-line 5)
      (evil-open-below 1))
    (run-hooks 'py-playground-hook)))

(defun py-playground-rm ()
  "Remove files of the current snippet together with directory of this snippet."
  (interactive)
  (if (py-playground-inside)
      (if (or (not py-playground-confirm-deletion)
              (y-or-n-p (format "Do you want delete whole snippet dir %s? "
                                (file-name-directory (buffer-file-name)))))
          (progn
            (run-hooks 'py-playground-rm-hook)
            (save-buffer)
            (let ((dir (file-name-directory (buffer-file-name))))
              (delete-directory dir t t)
              (dolist (buffer (buffer-list))
                (with-current-buffer buffer
                  (when (equal default-directory dir)
                    (let (kill-buffer-query-functions)
                      (kill-buffer buffer))))))))
    (message "Won't delete this! Because %s is not under the path %s. Remove the snippet manually!"
             (buffer-file-name) py-playground-basedir)))

(defun py-playground-snippet-unique-dir (prefix)
  "Get unique directory with PREFIX under `py-playground-basedir`."
  (let ((dir-name (concat py-playground-basedir "/"
                          (if (and prefix py-playground-ask-file-name) (concat prefix "-"))
                          (time-stamp-string "default--%:y-%02m-%02d-%02H%02M%02S"))))
    (make-directory dir-name t)
    dir-name))

(defun py-playground-inside ()
  "Is the current buffer is valid py-playground buffer."
  (if (string-match-p (file-truename py-playground-basedir) (file-truename (buffer-file-name)))
      (bound-and-true-p py-playground-mode)))

(provide 'py-playground)

;;; py-playground.el ends here
