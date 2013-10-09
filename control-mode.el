;;; control-mode.el --- A "control" mode, similar to vim's "normal" mode

;; Copyright (C) 2013 Stephen Marsh

;; Author: Stephen Marsh <stephen.david.marsh@gmail.com>
;; Version: 0.1
;; URL: https://github.com/stephendavidmarsh/control-mode
;; Keywords: convenience emulations

;; Control mode is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Control mode is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Control mode.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Control mode is a minor mode for Emacs that provides a
;; "control" mode, similar in purpose to vim's "normal" mode. Unlike
;; the various vim emulation modes, the key bindings in Control mode
;; are derived from the key bindings already setup, usually by making
;; the control key unnecessary, e.g. "Ctrl-f" becomes "f". This
;; provides the power of a mode dedicated to controlling the editor
;; without needing to learn or maintain new key bindings. See
;; https://github.com/stephendavidmarsh/control-mode for complete
;; documentation.

;;; Code:

(defvar control-mode-overrideable-bindings '(nil self-insert-command undefined))

;; Ignore Control-M
(defvar control-mode-ignore-events '(13))

;; This can't be control-mode-map because otherwise the
;; define-minor-mode will try to install it as the minor mode keymap,
;; despite being told the minor mode doesn't have a keymap.
(defvar control-mode-keymap (make-sparse-keymap))

(defvar control-mode-keymap-generation-functions '())

(defvar control-mode-conversion-cache '())

(defvar control-mode-emulation-alist nil)
(make-variable-buffer-local 'control-mode-emulation-alist)

(defvar control-mode-rebind-to-shift)

(defun control-mode-create-alist ()
  (setq control-mode-emulation-alist
        (let* ((mode-key (cons major-mode (sort (mapcar (lambda (x) (car (rassq x minor-mode-map-alist))) (current-minor-mode-maps)) 'string<)))
               (value (assoc mode-key control-mode-conversion-cache)))
          (if value (cdr value)
            (let ((newvalue (mapcar (lambda (x) (cons t x)) (cons (control-mode-create-hook-keymap) (cons control-mode-keymap (mapcar 'control-mode-get-converted-keymap-for (current-active-maps)))))))
              (push (cons mode-key newvalue) control-mode-conversion-cache)
              newvalue)))))

(defun control-mode-create-hook-keymap ()
  (let ((keymap (make-sparse-keymap)))
    (run-hook-with-args 'control-mode-keymap-generation-functions keymap)
    keymap))

(defun control-mode-mod-modifiers (event f)
  (event-convert-list (append (funcall f (remq 'click (event-modifiers event))) (list (event-basic-type event)))))


(defun control-mode/key-bindingv (e)
  (key-binding (vector e)))
(defun control-mode/remove-modifier (event mod)
  (control-mode-mod-modifiers event (lambda (x) (remq mod x))))
(defun control-mode/add-modifier (event mod)
  (control-mode-mod-modifiers event (lambda (x) (cons mod x))))
(defun control-mode/add-modifiers (event mod1 mod2)
  (control-mode-mod-modifiers event (lambda (x) (cons mod2 (cons mod1 x)))))
(defun control-mode/is-overrideable (b)
  (memq (control-mode/key-bindingv b) control-mode-overrideable-bindings))
(defun control-mode/add-binding (km e b)
  (define-key km (vector e) b))
(defun control-mode/try-to-rebind (km e b)
  (if (not (control-mode/is-overrideable e)) nil
    (control-mode/add-binding km e b)
    t))

(defun control-mode-get-converted-keymap-for (keymap)
  (let ((auto-keymap (make-sparse-keymap)))
    (map-keymap (lambda (ev bi) (control-mode-handle-binding ev bi auto-keymap))
                keymap)
    auto-keymap))

(defun control-mode-handle-binding (event binding auto-keymap)
  (unless (memq event control-mode-ignore-events)
    (if (memq 'control (event-modifiers event))
        (let ((newevent (control-mode/remove-modifier event 'control)))
          (when (control-mode/try-to-rebind auto-keymap newevent binding)
            (unless (memq 'meta (event-modifiers event)) ; Here to be safe, but Meta events should be inside Escape keymap
              (let ((cmbinding (control-mode/key-bindingv (control-mode/add-modifier event 'meta))))
                (when cmbinding
                  (control-mode/add-binding auto-keymap event cmbinding)
                  (let ((metaevent (control-mode/add-modifier newevent 'meta)))
                    (control-mode/try-to-rebind auto-keymap metaevent cmbinding)))))))))
  (when (and (eq event 27) (keymapp binding))
    (map-keymap (lambda (ev bi) (control-mode-handle-escape-binding ev bi auto-keymap))
                binding)))

(defun control-mode-handle-escape-binding (event binding auto-keymap)
  (unless (memq event control-mode-ignore-events)
    (if (memq 'control (event-modifiers event))
        (let ((only-meta (control-mode/add-modifier (remove-modifier event 'control) 'meta))
              (only-shift (control-mode/add-modifier (remove-modifier event 'control) 'shift)))
          (control-mode/try-to-rebind auto-keymap only-meta binding)
          (control-mode/try-to-rebind auto-keymap event binding)
          (if (and control-mode-rebind-to-shift
                   (not (memq 'shift (event-modifiers event)))
                   (not (control-mode/key-bindingv (control-mode/add-modifier only-shift 'control)))
                   (not (control-mode/key-bindingv (control-mode/add-modifier only-shift 'meta))))
              (control-mode/try-to-rebind auto-keymap only-shift binding)))
      (let ((control-instead (control-mode/add-modifier event 'control)))
        (when (and (control-mode/is-overrideable event)
                   (or (not (control-mode/key-bindingv control-instead))
                       (memq control-instead control-mode-ignore-events)))
          (control-mode/add-binding auto-keymap event binding)
          (let ((cmbinding (control-mode/key-bindingv (control-mode/add-modifiers event 'control 'meta))))
            (when cmbinding
              (control-mode/add-binding auto-keymap (control-mode/add-modifier event 'meta) cmbinding)
              (control-mode/add-binding auto-keymap control-instead cmbinding))))))))

;;;###autoload
(define-minor-mode control-mode
  "Toggle Control mode.
With a prefix argument ARG, enable Control mode if ARG
is positive, and disable it otherwise.  If called from Lisp,
enable the mode if ARG is omitted or nil.

Control mode is a global minor mode."
  nil " Control" nil (if control-mode (control-mode-setup) (control-mode-teardown)))

;;;###autoload
(define-globalized-minor-mode global-control-mode control-mode control-mode)

(add-hook 'emulation-mode-map-alists 'control-mode-emulation-alist)

(defun control-mode-setup ()
  (unless (string-prefix-p " *Minibuf" (buffer-name))
    (setq control-mode-emulation-alist nil)
    (control-mode-create-alist)))

(defun control-mode-teardown ()
  (setq control-mode-emulation-alist nil))

;;;###autoload
(defun control-mode-default-setup ()
  (define-key control-mode-keymap (kbd "C-z") 'global-control-mode)
  (global-set-key (kbd "C-z") 'global-control-mode)
  (add-hook 'control-mode-keymap-generation-functions
            'control-mode-ctrlx-hacks))

;;;###autoload
(defun control-mode-localized-setup ()
  (define-key control-mode-keymap (kbd "C-z") 'control-mode)
  (global-set-key (kbd "C-z") 'control-mode)
  (add-hook 'control-mode-keymap-generation-functions
            'control-mode-ctrlx-hacks))

(defun control-mode-ctrlx-hacks (keymap)
  (if (eq (key-binding (kbd "C-x f")) 'set-fill-column)
      (define-key keymap (kbd "x f") (lookup-key (current-global-map) (kbd "C-x C-f"))))
  (unless (key-binding (kbd "C-x x"))
    (define-key keymap (kbd "x x") (lookup-key (current-global-map) (kbd "C-x C-x")))))

(defun control-mode-reload-bindings ()
  "Force Control mode to reload all generated keybindings."
  (interactive)
  (setq control-mode-conversion-cache '())
  (mapc (lambda (buf)
          (with-current-buffer buf
            (if control-mode
                (control-mode-setup))))
        (buffer-list)))

(defcustom control-mode-rebind-to-shift nil
  "Allow rebinding Ctrl-Alt- to Shift-"
  :group 'control
  :type '(boolean)
  :set (lambda (x v)
         (setq control-mode-rebind-to-shift v)
         (control-mode-reload-bindings)))

(provide 'control-mode)

;;; control-mode.el ends here
