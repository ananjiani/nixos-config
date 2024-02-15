;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)
(setq doom-font (font-spec :family "Hack" :size 18 :weight 'normal))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(after! org
  (setq org-directory "~/Documents/org")
  (setq org-agenda-files (list "inbox.org" "./naarpr-dallas-notes/meeting-notes.org" "./red-notes/pc-meeting-notes.org"))
  (setq org-log-done 'note)
  (setq org-agenda-prefix-format '(
    (agenda  . " %i %?-12t% s%e ") ;; file name + org-agenda-entry-type
    (timeline  . "  % s")
    (todo  . " %i %e ")
    (tags  . " %i %-12:c")
    (search . " %i %-12:c")))
  (setq org-agenda-span 1
        org-agenda-start-day "+0d"
        org-agenda-skip-timestamp-if-done t
        org-agenda-skip-deadline-if-done t
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-scheduled-if-deadline-is-shown t
        org-agenda-skip-timestamp-if-deadline-is-shown t)
  ;; (setq org-agenda-hide-tags-regexp ".*")
  (setq org-agenda-category-icon-alist
        `(("tinker" ,(list (nerd-icons-faicon "nf-fa-cogs")) nil nil :ascent center)
          ("rare" ,(list (nerd-icons-faicon "nf-fa-pencil")) nil nil :ascent center)
          ("organizing" ,(list (nerd-icons-faicon "nf-fa-hand_rock_o")) nil nil :ascent center)
          ("naarpr" ,(list (nerd-icons-faicon "nf-fa-renren")) nil nil :ascent center)
          ("unit" ,(list (nerd-icons-faicon "nf-fa-rebel")) nil nil :ascent center)
          ("igf" ,(list (nerd-icons-faicon "nf-fae-dice")) nil nil :ascent center)
          ("ha" ,(list (nerd-icons-faicon "nf-fa-home")) nil nil :ascent center)
          ("personal" ,(list (nerd-icons-mdicon "nf-md-human")) nil nil :ascent center)
          ("work" ,(list (nerd-icons-faicon "nf-fa-graduation_cap")) nil nil :ascent center)
          ))
  (setq org-agenda-custom-commands
        '(("n" "NAARPR Dallas"
           ((tags-todo "naarpr")))
          ("u" "Unit"
           ((tags-todo "+CATEGORY=\"unit\""))
          )))
  ;; (setq org-agenda-todo-keyword-format "")
  (setq org-capture-templates `(
    ("i" "Inbox" entry (file "inbox.org") "* TODO %?\n/Entered on/ %U")
   )))

(define-key global-map (kbd "C-c c") 'org-capture)

(setq org-super-agenda-groups
    '(;; Each group has an implicit boolean OR operator between its selectors.
         ;; Set order of multiple groups at once
         ;; (:discard (:and (:category "unit " :not (:tag "@ammar"))))
         ;; (:discard (:and (:tag "naarpr" :not (:tag "@ammar"))))

         (:name "❗ Overdue"
                :scheduled past
                :deadline past
                :order 1
                :face 'error)
         (:name "📅 Today"
                :date today
                :scheduled today
                :deadline today
                :order 2
                :face 'warning)

         (:name "Work" :category "work" :order 4)
         (:order-multi (5 (:name "Organizing" :and (:category "organizing" :not (:tag "naarpr")))
                          (:name "Unit" :and (:category "unit" :tag "@ammar"))
                          (:name "NAARPR Dallas" :category "naarpr")
         ))
         (:name "IGF SPG" :category "igf" :order 6)
         (:name "RARE" :category "rare" :order 7)

         (:order-multi (8 (:name "Tinkering" :category "tinker")
                          (:name "Home Automation" :category "ha")
                          (:name "Weekly Habits" :tag "weekly")
                          (:name "Daily Habits" :tag "daily")
                          ))
         (:name "Personal" :category "personal" :order 3)
         ;; Groups supply their own section names when none are given

         (:order-multi (10 (:name "Unit (team)" :and (:category "unit" :not (:tag "@ammar")))
                           (:name "NAARPR Dallas (team)" :and (:category "naarpr" :not (:tag "@ammar")))
                           ))

         (:auto-category t :order 9)
         ))
         ;; After the last group, the agenda will display items that didn't
         ;; match any of these groups, with the default order position of 99


(setq org-super-agenda-header-map (make-sparse-keymap))

(org-super-agenda-mode t)
(setq org-agenda-skip-function-global '(org-agenda-skip-entry-if 'todo 'done))

(defun org-agenda-open-hook()
  (olivetti-mode)
  (olivetti-set-width 120))


(add-hook 'org-agenda-mode-hook 'org-agenda-open-hook)
(with-eval-after-load 'org (global-org-modern-mode))

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
