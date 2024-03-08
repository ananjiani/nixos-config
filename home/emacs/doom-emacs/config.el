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
(setq vterm-timer-delay 0.01
      vterm-shell "fish")
;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(after! org
  (setq org-directory "~/Documents/org-roam")
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
          ("work" ,(list (nerd-icons-faicon "nf-fa-graduation_cap")) nil nil :ascent center)))

  (setq org-agenda-custom-commands
        '(("n" "NAARPR Dallas"
           ((org-ql-block '(and (todo "TODO")
                                (tags "@ammar")
                                (tags "naarpr"))
                          ((org-ql-block-header "Ammar's Tasks")))
            (org-ql-block '(and (todo "TODO")
                                (not (tags "@ammar"))
                                (tags "naarpr"))
                          ((org-ql-block-header "Everyone else's Tasks")))
            (org-ql-block '(and (todo)
                                (not (todo "TODO"))
                                (tags "naarpr"))
                          ((org-ql-block-header "Backlog")))))


          ("u" "Unit"
           ((org-ql-block '(and (todo "TODO")
                                (tags "@ammar")
                                (category "unit"))
                          ((org-ql-block-header "Ammar's Tasks")))
            (org-ql-block '(and (todo "TODO")
                                (not (tags "@ammar"))
                                (category "unit"))
                          ((org-ql-block-header "Everyone else's Tasks")))

            (org-ql-block '(and (todo)
                                (not (todo "TODO"))
                                (category "unit"))
                          ((org-ql-block-header "Backlog")))))



          ("w" "Work"
           ((org-ql-block '(and (category "work")
                                (todo "TODO"))
                          ((org-ql-block-header "Tasks")))

            (org-ql-block '(and (category "work")
                                (todo)
                                (not (todo "TODO")))

                          ((org-ql-block-header "Backlog")))))))


  ;; (setq org-agenda-todo-keyword-format "")
  (setq org-capture-templates `(
                                ("i" "Inbox" entry (file "inbox.org") "* TODO %?\n/Entered on/ %U"))))

(setq org-roam-directory "~/Documents/org-roam")
;; (org-roam-db-autosync-mode)
;; (setq org-roam-database-connector 'emacsql-sqlite-builtin)

(define-key global-map (kbd "C-c c") 'org-capture)

(setq org-super-agenda-groups
      '(;; Each group has an implicit boolean OR operator between its selectors.
        ;; Set order of multiple groups at once
        ;; (:discard (:and (:category "unit " :not (:tag "@ammar"))))
        ;; (:discard (:and (:tag "naarpr" :not (:tag "@ammar"))))

        (:name "Habits"
         :tag "daily"
         :order 0
         :face 'warning)
        (:order-multi (10 (:name "Unit (team)" :and (:category "unit" :not (:tag "@ammar")))
                          (:name "NAARPR Dallas (team)" :and (:category "naarpr" :not (:tag "@ammar")))))
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
                         (:name "NAARPR Dallas" :and (:category "naarpr" :tag "@ammar"))))

        (:name "IGF SPG" :category "igf" :order 6)
        (:name "RARE" :category "rare" :order 7)

        (:order-multi (8 (:name "Tinkering" :category "tinker")
                         (:name "Home Automation" :category "ha")
                         (:name "Weekly Habits" :tag "weekly")
                         (:name "Daily Habits" :tag "daily")))

        (:name "Personal" :category "personal" :order 3)
        ;; Groups supply their own section names when none are given

        (:auto-category t :order 9)))

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

(setq +format-on-save-enabled-modes
      '(not emacs-lisp-mode))

(defun fzf-home ()
  (interactive)
  (fzf-find-file-in-dir "~"))

(map! :leader
      (:prefix ("z" . "Fuzzy Find")
               (:desc "Current directory" "f" #'fzf
                :desc "Directory" "d" #'fzf-directory
                :desc "Home" "h" #'fzf-home)))

(defun my-nov-font-setup ()
  (face-remap-add-relative 'variable-pitch :family "Liberation Serif"
                           :height 1.0))

(after! nov
  (evil-collection-nov-setup)
  (org-remark-mode)
  (org-remark-nov-mode)
  (setq nov-text-width t)
  (setq visual-fill-column-center-text t))

(add-hook 'nov-mode-hook 'visual-line-mode)
(add-hook 'nov-mode-hook 'visual-fill-column-mode)
(add-hook 'nov-mode-hook 'my-nov-font-setup)
(add-hook 'nov-mode-hook 'org-agenda-open-hook)
(add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode))

(use-package! org-remark
  :bind (;; :bind keyword also implicitly defers org-remark itself.
         ;; Keybindings before :map is set for global-map.
         ("C-c n m" . org-remark-mark)
         ("C-c n l" . org-remark-mark-line) ; new in v1.3
         :map org-remark-mode-map
         ("C-c n o" . org-remark-open)
         ("C-c n ]" . org-remark-view-next)
         ("C-c n [" . org-remark-view-prev)
         ("C-c n r" . org-remark-remove)
         ("C-c n d" . org-remark-delete))
  ;; Alternative way to enable `org-remark-global-tracking-mode' in
  ;; `after-init-hook'.
  ;; :hook (after-init . org-remark-global-tracking-mode)
  :init
  ;; It is recommended that `org-remark-global-tracking-mode' be
  ;; enabled when Emacs initializes. Alternatively, you can put it to
  ;; `after-init-hook' as in the comment above
  (org-remark-global-tracking-mode +1)
  :config
  (use-package! org-remark-info :after info :config (org-remark-info-mode +1))
  (use-package! org-remark-eww  :after eww  :config (org-remark-eww-mode +1))
  (use-package! org-remark-nov  :after nov  :config (org-remark-nov-mode +1)))
(after! org-remark
  (tooltip-mode +1)
  (setq org-remark-notes-file-name
        (lambda ()
          (concat "~/Documents/org-roam/"
                  (file-name-base (org-remark-notes-file-name-function))
                  ".org"))))

(use-package! consult-org-roam
  :after org-roam
  :init
  (require 'consult-org-roam)
  ;; Activate the minor mode
  (consult-org-roam-mode 1)
  :custom
  (consult-org-roam-grep-func #'consult-ripgrep)
  (consult-org-roam-buffer-narrow-key ?r)
  (consult-org-roam-buffer-after-buffers t)
  :config
  (consult-customize
   consult-org-roam-forward-links
   :preview-key "M-."))

(map! :leader
      (:prefix ("nr")
               (:desc "backlinks" "b" #'consult-org-roam-backlinks
                :desc "backlinks recursive" "B" #'consult-org-roam-backlinks-recursive
                :desc "forward links" "l" #'consult-org-roam-forward-links
                :desc "search" "S" #'consult-org-roam-search)))

;; :bind
;; ("SPC n r e" . consult-org-roam-file-find)
;; ("SPC n r b" . consult-org-roam-backlinks)
;; ("SPC n r B" . consult-org-roam-backlinks-recursive)
;; ("SPC n r l" . consult-org-roam-forward-links)
;; ("SPC n r S" . consult-org-roam-search))


(defun org-roam-subtree-aware-preview-function ()
  "Same as `org-roam-preview-default-function', but gets entire subtree in specific buffers."
  (if (--> (org-roam-node-at-point)
           (org-roam-node-file it)
           (or (member it
                       ;; This is a list of buffers where I want to see preview of subtree
                       org-roam-subtree-aware-preview-buffers)
               (f-ancestor-of-p bibtex-completion-notes-path it)))
      (let ((beg (progn (org-roam-end-of-meta-data t)
                        (point)))
            (end (progn (org-previous-visible-heading 1)
                        (org-end-of-subtree)
                        (point))))
        (-reduce
         (lambda (str el)
           ;; remove properties not interested. If prop drawer is empty at the end, remove drawer itself
           (s-replace-regexp (format "\n *:%s:.*$" el) "" str))
         ;; remove links
         (list (s-replace-regexp "\\[id:\\([a-z]\\|[0-9]\\)\\{8\\}-\\([a-z]\\|[0-9]\\)\\{4\\}-\\([a-z]\\|[0-9]\\)\\{4\\}-\\([a-z]\\|[0-9]\\)\\{4\\}-\\([a-z]\\|[0-9]\\)\\{12\\}\\]"
                                 ""
                                 (string-trim (buffer-substring-no-properties beg end)))
               "INTERLEAVE_PAGE_NOTE" "BRAIN_CHILDREN" okm-parent-property-name "PROPERTIES:\n *:END")))
    (org-roam-preview-default-function))

  (setq org-roam-preview-function #'org-roam-subtree-aware-preview-function))

(defun my/org-roam-filter-by-tag (tag-name)
  (lambda (node)
    (member tag-name (org-roam-node-tags node))))

(defun my/org-roam-list-notes-by-tag (tag-name)
  (mapcar #'org-roam-node-file
          (seq-filter
           (my/org-roam-filter-by-tag tag-name)
           (org-roam-node-list))))

(defun my/org-roam-refresh-agenda-list ()
  (interactive)
  (setq org-agenda-files (my/org-roam-list-notes-by-tag "agenda")))

;; Build the agenda list the first time for the session
(my/org-roam-refresh-agenda-list)

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
