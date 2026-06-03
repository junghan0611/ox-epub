;;; ox-epub.el --- Export org mode projects to EPUB -*- lexical-binding: t; -*-

;; Copyright (c) 2017-2018 - Mark Meyer

;; Author: Mark Meyer <mark@ofosos.org>
;; Maintainer: Mark Meyer <mark@ofosos.org>

;; URL: http://github.com/ofosos/org-epub
;; Keywords: hypermedia

;; Version: 0.1.0

;; Package-Requires: ((emacs "24.3") (org "9"))

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

;; This is an addition to the standard org-mode exporters.  The package
;; extends the (X)HTML exporter to produce EPUB files.  It eliminates
;; all inline CSS and JavaScript to accomplish this.  This exporter
;; will also tie the XHTML DTD to XHTML 1.1, a concrete DTD specifier
;; that was not supported by ox-html previously.

;; The main part is the generation of the table of contents in machine
;; readable form, as well as the spine, which defines the order in
;; which files are presented.  A lesser part is the inclusion of
;; various metadata properties, among them authorship and rights.

;;; Code:

(require 'cl-lib)
(require 'ox-publish)
(require 'ox-html)
(require 'org-element)

(org-export-define-derived-backend 'epub 'html
  :options-alist
  '((:epub-uid "UID" nil nil t)
    (:epub-subject "Subject" nil nil t)
    (:epub-description "Description" nil nil t)
    (:epub-publisher "Publisher" nil nil t)
    (:epub-rights "License" nil nil t)
    (:epub-style "EPUBSTYLE" nil nil t)
    (:epub-cover "EPUBCOVER" nil nil t)
    (:html-doctype "HTML_DOCTYPE" nil "xhtml" t))
    
  :translate-alist
  '((template . org-epub-template)
    (link . org-epub-link)
    (latex-environment . org-epub--latex-environment)
    (latex-fragment . org-epub--latex-fragment))
  :menu-entry
  '(?E "Export to Epub"
       ((?e "As Epub file" org-epub-export-to-epub)
	(?O "As Epub file and open"
	    (lambda (a s v b)
	      (if a (org-epub-export-to-epub t s v)
		(org-open-file (org-epub-export-to-epub nil s v) 'system)))))))

(defvar org-epub-zip-dir nil
  "The temporary directory to export to")

(defvar org-epub-style-default "
  .title  { text-align: center;
             margin-bottom: .2em; }
  .subtitle { text-align: center;
              font-size: medium;
              font-weight: bold;
              margin-top:0; }
  .todo   { font-family: monospace; color: red; }
  .done   { font-family: monospace; color: green; }
  .priority { font-family: monospace; color: orange; }
  .tag    { background-color: #eee; font-family: monospace;
            padding: 2px; font-size: 80%; font-weight: normal; }
  .timestamp { color: #bebebe; }
  .timestamp-kwd { color: #5f9ea0; }
  .org-right  { margin-left: auto; margin-right: 0px;  text-align: right; }
  .org-left   { margin-left: 0px;  margin-right: auto; text-align: left; }
  .org-center { margin-left: auto; margin-right: auto; text-align: center; }
  .underline { text-decoration: underline; }
  #postamble p, #preamble p { font-size: 90%; margin: .2em; }
  p.verse { margin-left: 3%; }
  pre {
    border: 1px solid #ccc;
    box-shadow: 3px 3px 3px #eee;
    padding: 8pt;
    font-family: monospace;
    overflow: auto;
    margin: 1.2em;
  }
  pre.src {
    position: relative;
    overflow: visible;
    padding-top: 1.2em;
  }

  table { border-collapse:collapse; }
  caption.t-above { caption-side: top; }
  caption.t-bottom { caption-side: bottom; }
  td, th { vertical-align:top;  }
  th.org-right  { text-align: center;  }
  th.org-left   { text-align: center;   }
  th.org-center { text-align: center; }
  td.org-right  { text-align: right;  }
  td.org-left   { text-align: left;   }
  td.org-center { text-align: center; }
  dt { font-weight: bold; }
  .footpara { display: inline; }
  .footdef  { margin-bottom: 1em; }
  .figure { padding: 1em; }
  .figure p { text-align: center; }
  .inlinetask {
    padding: 10px;
    border: 2px solid gray;
    margin: 10px;
    background: #ffffcc;
  }
  #org-div-home-and-up
   { text-align: right; font-size: 70%; white-space: nowrap; }
  textarea { overflow-x: auto; }
  .linenr { font-size: smaller }
  .code-highlighted { background-color: #ffff00; }
  .org-info-js_info-navigation { border-style: none; }
  #org-info-js_console-label
    { font-size: 10px; font-weight: bold; white-space: nowrap; }
  .org-info-js_search-highlight
    { background-color: #ffff00; color: #000000; font-weight: bold; }
  .org-svg { max-width: 90%; height: auto; }

"
  "Default style declarations for org epub")

(defvar org-epub-zip-command "zip"
  "Command to call to create zip files.")

(defvar org-epub-zip-no-compress (list "-Xu0")
  "Zip command option list to pass for no compression.")

(defvar org-epub-zip-compress (list "-Xu9")
  "Zip command option list to pass for compression.")

(defvar org-epub-metadata nil
  "EPUB export metadata")

(defvar org-epub-headlines nil
  "EPUB headlines")

(defvar org-epub-style-counter 0
  "EPUB style counter")

;; manifest mechanism

(defvar org-epub-manifest nil
  "EPUB export manifest")

(defun org-epub-manifest-entry (id filename type mimetype &optional source properties)
  "Create a manifest entry with the given ID, FILENAME, TYPE, MIMETYPE and optional SOUCE.

FILENAME should be the new name in the epub container. TYPE
should be one of `'html', `'stylesheet', `'coverimg', `'cover',
`'img' or `'nav'. If SOURCE is given the file name by SOUCE will be
copied to FILENAME at the end of the export process.  PROPERTIES, when
non-nil, is the EPUB3 manifest item `properties' attribute value
\(e.g. \"nav\", \"cover-image\", \"svg\")."
  (list :id id :filename filename :type type :mimetype mimetype
	:source source :properties properties))

(defun org-epub-cover-p (manifest-entry)
  "Determine if MANIFEST-ENTRY is of type cover."
  (eq (plist-get manifest-entry :type) 'cover))

(defun org-epub-coverimg-p (manifest-entry)
  "Determine if MANIFEST-ENTRY is of type cover image."
  (eq (plist-get manifest-entry :type) 'coverimg))

(defun org-epub-style-p (manifest-entry)
  "Determine if MANIFEST-ENTRY is of type stylesheet."
  (eq (plist-get manifest-entry :type) 'stylesheet))

(defun org-epub-manifest-needcopy (manifest-entry)
  "Determine if MANIFEST-ENTRY needs to be copied.

If it needs to be copied return a pair (sourcefile . targetfile)."
  (if (plist-get manifest-entry :source)
      (cons (plist-get manifest-entry :source)
	    (plist-get manifest-entry :filename))
    nil))

(defun org-epub-manifest-all (pred)
  "Return all manifest entries for which PRED is true."
  (cl-remove-if-not pred org-epub-manifest))

(cl-defun org-epub-manifest-first (pred)
  "Return the first manifest entry for which PRED is true."
  (let ((val))
    (dolist (el org-epub-manifest val)
      (when (funcall pred el)
	(cl-return-from org-epub-manifest-first el)))))

;; EPUB 3.0 helpers

(defun org-epub--mime-type (ext)
  "Return the IANA media type for image file extension EXT.
EPUB3 treats SVG as a core media type, so it must carry the correct
`image/svg+xml' type (plain `image/svg' triggers an RSC-032 foreign
resource fallback error)."
  (let ((ext (downcase (or ext ""))))
    (cond ((string= ext "svg") "image/svg+xml")
	  ((member ext '("jpg" "jpeg")) "image/jpeg")
	  ((string= ext "png") "image/png")
	  ((string= ext "gif") "image/gif")
	  ((member ext '("tif" "tiff")) "image/tiff")
	  ((string= ext "webp") "image/webp")
	  (t (concat "image/" ext)))))

(defun org-epub--png-size (file)
  "Read (WIDTH . HEIGHT) from PNG FILE header bytes, no display needed."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil 0 24)
    (let ((b (lambda (i) (aref (buffer-string) i))))
      ;; PNG: 8B signature, IHDR len(4)+"IHDR"(4), width@16, height@20 (big-endian)
      (cons (logior (ash (funcall b 16) 24) (ash (funcall b 17) 16)
		    (ash (funcall b 18) 8) (funcall b 19))
	    (logior (ash (funcall b 20) 24) (ash (funcall b 21) 16)
		    (ash (funcall b 22) 8) (funcall b 23))))))

(defun org-epub--jpeg-size (file)
  "Read (WIDTH . HEIGHT) from JPEG FILE by scanning SOF markers.
Buffer positions are 1-based; positions 1-2 hold the SOI (FF D8) so the
first segment's marker prefix sits at position 3.  Each segment is
FF <marker> <len-hi> <len-lo> <data...> where LEN counts the two length
bytes; SOF markers (C0-CF except C4/C8/CC) carry precision(1),
height(2), width(2)."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (let ((max (point-max)) (pos 3) result)
      (while (and (not result) (< (+ pos 1) max))
	(if (/= (char-after pos) #xFF)
	    ;; resync on fill bytes / unexpected data
	    (setq pos (1+ pos))
	  (let ((marker (char-after (1+ pos))))
	    (cond
	     ;; SOF markers carry the frame dimensions
	     ((and (>= marker #xC0) (<= marker #xCF)
		   (not (memq marker '(#xC4 #xC8 #xCC))))
	      (setq result
		    (cons (logior (ash (char-after (+ pos 7)) 8) (char-after (+ pos 8)))
			  (logior (ash (char-after (+ pos 5)) 8) (char-after (+ pos 6))))))
	     ;; standalone markers without a length payload
	     ((or (memq marker '(#xD8 #xD9 #x01))
		  (and (>= marker #xD0) (<= marker #xD7)))
	      (setq pos (+ pos 2)))
	     ;; ordinary segment: skip past its 2-byte length
	     (t
	      (setq pos (+ pos 2 (logior (ash (char-after (+ pos 2)) 8)
					 (char-after (+ pos 3))))))))))
      result)))

(defun org-epub--image-pixel-size (file)
  "Return (WIDTH . HEIGHT) in pixels for image FILE.
Reads the dimensions directly from the file header so it works in a
headless Emacs (daemon / --batch), where `image-size' would signal
\"Window system frame should be used\".  Falls back to `image-size' for
formats not understood from the header (that path needs a graphic
frame)."
  (let ((ext (downcase (or (file-name-extension file) ""))))
    (or (cond ((string= ext "png") (ignore-errors (org-epub--png-size file)))
	      ((member ext '("jpg" "jpeg")) (ignore-errors (org-epub--jpeg-size file)))
	      (t nil))
	(image-size (create-image (expand-file-name file)) t))))

(defun org-epub--valid-uuid-p (s)
  "Return non-nil when S is a syntactically valid (urn:)uuid."
  (and (stringp s)
       (string-match-p
	(concat "\\`\\(urn:uuid:\\)?"
		"[0-9a-fA-F]\\{8\\}-[0-9a-fA-F]\\{4\\}-[0-9a-fA-F]\\{4\\}-"
		"[0-9a-fA-F]\\{4\\}-[0-9a-fA-F]\\{12\\}\\'")
	s)))

(defun org-epub--normalize-uid (uid)
  "Return a valid unique identifier derived from UID.
A valid UUID is kept (prefixed with `urn:uuid:').  A value that claims
to be a UUID (\"urn:uuid:...\") but is malformed, or a missing value,
is replaced by a freshly generated v4 UUID.  Any other string (e.g. a
URL or ISBN URI) is a legal EPUB identifier and is left untouched."
  (require 'org-id)
  (let ((uid (and (stringp uid) (string-trim uid))))
    (cond
     ((or (null uid) (string= uid ""))
      (concat "urn:uuid:" (org-id-uuid)))
     ((org-epub--valid-uuid-p uid)
      (if (string-prefix-p "urn:uuid:" uid) uid (concat "urn:uuid:" uid)))
     ((string-prefix-p "urn:uuid:" uid)
      (concat "urn:uuid:" (org-id-uuid)))
     (t uid))))

(defun org-epub--now-utc ()
  "Return the current time as an EPUB3 `dcterms:modified' string (UTC)."
  (format-time-string "%Y-%m-%dT%H:%M:%SZ" nil t))

(defconst org-epub--xml-builtin-entities '("amp" "lt" "gt" "quot" "apos")
  "Named entities predefined in XML; every other must become a literal char.")

(defconst org-epub--html-entity-extra
  '(("lsquo" . "‘") ("rsquo" . "’") ("ldquo" . "“") ("rdquo" . "”")
    ("sbquo" . "‚") ("bdquo" . "„") ("ensp" . " ") ("emsp" . " ")
    ("thinsp" . " ") ("frac12" . "½") ("frac14" . "¼") ("frac34" . "¾"))
  "Named HTML entities `ox-html' emits that `org-entities' does not cover
\(smart quotes, fixed-width spaces, fractions).")

(defvar org-epub--entity-table nil
  "Lazily built hash mapping an HTML entity name to its literal string.")

(defun org-epub--entity-table ()
  "Return the HTML-entity-name -> literal-char hash, building it once.
Derived from `org-entities'/`org-entities-user' (covers `\\alpha', `\\le',
`\\ndash' …, i.e. every entity Org itself can emit) plus the typographic
extras in `org-epub--html-entity-extra'."
  (or org-epub--entity-table
      (let ((tbl (make-hash-table :test 'equal)))
	(require 'org-entities)
	(dolist (e (append (bound-and-true-p org-entities-user)
			   (bound-and-true-p org-entities)))
	  (when (and (consp e) (>= (length e) 7))
	    (let ((html (nth 3 e)) (utf8 (nth 6 e)))
	      (when (and (stringp html) (stringp utf8)
			 (string-match "\\`&\\([a-zA-Z][a-zA-Z0-9]*\\);\\'" html))
		(puthash (match-string 1 html) utf8 tbl)))))
	(dolist (pair org-epub--html-entity-extra)
	  (puthash (car pair) (cdr pair) tbl))
	(setq org-epub--entity-table tbl))))

(defun org-epub--xmlify (text)
  "Convert non-builtin named HTML entities in TEXT to literal characters.
Under the EPUB3 `<!DOCTYPE html>' (parsed as XML) only the five XML
builtin entities are declared; `&ndash;' `&mdash;' `&hellip;' `&alpha;'
etc. would otherwise become undeclared-entity (RSC-016) parse errors.
Numeric references (`&#NNNN;') are always valid in XML and are kept."
  (let ((tbl (org-epub--entity-table)))
    (replace-regexp-in-string
     "&\\([a-zA-Z][a-zA-Z0-9]*\\);"
     (lambda (m)
       (let ((name (match-string 1 m)))
	 (cond
	  ((member name org-epub--xml-builtin-entities) m)
	  ((gethash name tbl))
	  (t m))))
     text t t)))

(defun org-epub--xml-escape (s)
  "Escape XML metacharacters in string S for element text or attributes.
Also escapes the double quote so the result is safe inside a
double-quoted attribute value.  Use for raw (un-transcoded) values such
as the document identifier; do NOT use on values already produced by
`org-export-data', which are HTML-escaped."
  (if (not (stringp s)) s
    (let ((s (replace-regexp-in-string "&" "&amp;" s t t)))
      (setq s (replace-regexp-in-string "<" "&lt;" s t t))
      (setq s (replace-regexp-in-string ">" "&gt;" s t t))
      (replace-regexp-in-string "\"" "&quot;" s t t))))

;; core

;;; Latex Environment - stolen from ox-html

(defun org-epub--latex-environment (latex-environment _contents info)
  "Transcode a LATEX-ENVIRONMENT element from Org to HTML.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (let ((processing-type (plist-get info :with-latex))
	(latex-frag (org-remove-indentation
		     (org-element-property :value latex-environment)))
	(attributes (org-export-read-attribute :attr_html latex-environment)))
    (cond
     ((assq processing-type org-preview-latex-process-alist)
      (let ((formula-link
	     (org-html-format-latex latex-frag processing-type info)))
	(when (and formula-link (string-match "file:\\([^]]*\\)" formula-link))
	  ;; Do not provide a caption or a name to be consistent with
	  ;; `mathjax' handling.
	  (org-html--wrap-image
	   (org-html--format-image
	    (let* ((path (match-string 1 formula-link))
		   (ref (org-export-get-reference latex-environment info))
		   (mime (file-name-extension path))
		   (name (concat "img-" ref "." mime)))
	      (message "Formatting Latex environment: %s" name)
	      (push (org-epub-manifest-entry ref name 'img (org-epub--mime-type mime) path) org-epub-manifest)
	      name) attributes info) info))))
     (t latex-frag))))

;;;; Latex Fragment - stolen from ox-html

(defun org-epub--latex-fragment (latex-fragment _contents info)
  "Transcode a LATEX-FRAGMENT object from Org to HTML.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (let ((latex-frag (org-element-property :value latex-fragment))
	(processing-type (plist-get info :with-latex)))
    (cond
     ((assq processing-type org-preview-latex-process-alist)
      (let ((formula-link
	     (org-html-format-latex latex-frag processing-type info)))
	(when (and formula-link (string-match "file:\\([^]]*\\)" formula-link))
	  (let* ((path (match-string 1 formula-link))
		 (ref (org-export-get-reference latex-fragment info))
		 (mime (file-name-extension path))
		 (name (concat "img-" ref "." mime)))
	    (message "Formatting Latex fragement: %s" name)
	    (push (org-epub-manifest-entry ref name 'img (org-epub--mime-type mime) path) org-epub-manifest)
	    (org-html--format-image name nil info)))))
     (t latex-frag))))


(defun org-epub-link (link desc info)
  "Return the HTML required for a link descriped by LINK, DESC, and INFO.

See org-html-link for more info."
  (when (org-export-inline-image-p link (plist-get info :html-inline-image-rules))
    (let* ((path (org-link-unescape (org-element-property :path link)))
	   (ref (org-export-get-reference link info))
	   (mime (file-name-extension path))
	   (name (concat "img-" ref "." mime)))
      (push (org-epub-manifest-entry ref name 'img (org-epub--mime-type mime) path) org-epub-manifest)
      (org-element-put-property link :path name)))
  (org-html-link link desc info))

(defun org-epub-meta-put (symbols info)
  "Put SYMBOLS taken from INFO into the org-epub metadata cache."
  (mapc
   #'(lambda (sym)
       (let ((data (plist-get info sym)))
	 (setq org-epub-metadata
	       (plist-put org-epub-metadata sym
			  (if (listp data)
			      (org-export-data data info)
			    data)))))
   symbols))

(defun org-epub-template (contents info)
  "Return complete document string after HTML conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options."
  (org-epub-meta-put '(:epub-uid :title :language :epub-subject :epub-description :author
				 :epub-publisher :date :epub-rights :html-head-include-default-style :epub-cover :epub-style) info)
  (setq org-epub-metadata (plist-put org-epub-metadata :epub-toc-depth 2))
  ;; EPUB3 requires a syntactically valid identifier (OPF-085); normalise the
  ;; UID once here so content.opf and toc.ncx stay in sync.
  (setq org-epub-metadata
	(plist-put org-epub-metadata :epub-uid
		   (org-epub--normalize-uid (plist-get org-epub-metadata :epub-uid))))
  ;; maybe set toc-depth "2" to some dynamic value
  (setq org-epub-headlines
	(mapcar (lambda (headline)
		  (list
		   (org-element-property :raw-value headline)
		   (org-element-property :level headline)
		   (org-export-get-reference headline info)))
		(org-export-collect-headlines info 2)))
  (let ((styles (split-string (or (plist-get org-epub-metadata :epub-style) " "))))
    (mapc #'(lambda (style)
	      (let* ((stylenum (cl-incf org-epub-style-counter))
		     (stylename (concat "style-" (format "%d" stylenum)))
		     (stylefile (concat stylename ".css")))
		(push (org-epub-manifest-entry stylename stylefile 'stylesheet "text/css" style) org-epub-manifest)))
	  styles))
  (concat
   (when (and (not (org-html-html5-p info)) (org-html-xhtml-p info))
     (let* ((xml-declaration (plist-get info :html-xml-declaration))
	    (decl (or (and (stringp xml-declaration) xml-declaration)
		      (cdr (assoc (plist-get info :html-extension)
				  xml-declaration))
		      (cdr (assoc "html" xml-declaration))
		      "")))
       (when (not (or (not decl) (string= "" decl)))
	 (format "%s\n"
		 (format decl
			 (or (and org-html-coding-system
				  (fboundp 'coding-system-get)
				  (coding-system-get org-html-coding-system 'mime-charset))
			     "iso-8859-1"))))))
   "<!DOCTYPE html>"
   "\n"
   (concat "<html"
	   (format
	    " xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"%s\" xml:lang=\"%s\""
	    (plist-get info :language) (plist-get info :language))
	   ">\n")
   
   "<head>\n"
   (org-html--build-meta-info info)
   (when (plist-get info :html-head-include-default-style)
     "<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>\n")
   (when (plist-get info :epub-style)
     (mapconcat
      #'(lambda (entry)
	  (concat "<link rel=\"stylesheet\" type=\"text/css\" href=\"" (plist-get entry :filename) "\"/>\n"))
      (org-epub-manifest-all #'org-epub-style-p) "\n"))
   "</head>\n"
   "<body>\n"
   ;; Preamble.
   (org-html--build-pre/postamble 'preamble info)
   ;; Document contents.
					;   (let ((div (assq 'content (plist-get info :html-divs))))
					;     (format "<%s id=\"%s\">\n" (nth 1 div) (nth 2 div)))
   "<div id=\"content\">"
   ;; Document title.
   (when (plist-get info :with-title)
     (let ((ftitle (plist-get info :title))
	   (subtitle (plist-get info :subtitle)))
       (when ftitle
	 (message (org-export-data ftitle info))
	 (format
	  "<h1 class=\"title\">%s</h1>%s\n"
	  (org-export-data ftitle info)
	  (if subtitle
	      (format
	       "<p class=\"subtitle\">%s</p>\n"
	       (org-export-data subtitle info))
	    "")))))
     contents
     "</div>"
     ;   (format "</%s>\n" (nth 1 (assq 'content (plist-get info :html-divs))))
     ;; Postamble.
     (org-html--build-pre/postamble 'postamble info)
     ;; Closing document.
     "</body>\n</html>"))

;; see ox-odt

(defmacro org-epub--export-wrapper (outfile &rest body)
  "Export an Epub with BODY generating the main html file and OUTFILE as target file."
  `(let* ((outfile ,outfile)
	      (org-epub-manifest nil)
	      (org-epub-metadata nil)
	      ;; HTML5/EPUB3 rejects the obsolete presentational table
	      ;; attributes ox-html emits by default (border/cellspacing/...).
	      (org-html-table-default-attributes nil)
	      (org-epub-style-counter 0)
	      (out-file-type (file-name-extension outfile))
	      (org-epub-zip-dir (file-name-as-directory
				 (make-temp-file (format "%s-" out-file-type) t)))
	      (body ,@body))
     (condition-case err
	 (progn
	   (when (plist-get org-epub-metadata :html-head-include-default-style)
	     (with-current-buffer (find-file (concat org-epub-zip-dir "style.css"))
	       (insert org-epub-style-default)
	       (save-buffer 0)
	       (kill-buffer)
	       (push (org-epub-manifest-entry "default-style" "style.css" 'stylesheet "text/css") org-epub-manifest)))
	   (when (org-string-nw-p (plist-get org-epub-metadata :epub-cover))
	     (let* ((cover-path (plist-get org-epub-metadata :epub-cover))
		    (cover-type (file-name-extension cover-path))
		    (cover-size (org-epub--image-pixel-size (expand-file-name cover-path)))
		    (cover-width (car cover-size))
		    (cover-height (cdr cover-size))
		    (cover-name (concat "cover." cover-type)))
	       (with-current-buffer (find-file (concat org-epub-zip-dir "cover.html"))
		 (erase-buffer)
		 (insert
		  (org-epub-template-cover cover-name cover-width cover-height
					   (plist-get org-epub-metadata :title)))
		 (save-buffer 0)
		 (kill-buffer)
		 (let ((men (org-epub-manifest-entry "cover" "cover.html" 'cover "application/xhtml+xml" nil "svg")))
		   (push men org-epub-manifest))
		 (let ((men (org-epub-manifest-entry "cover-image" cover-name 'coverimg (org-epub--mime-type cover-type) cover-path "cover-image")))
		   (push men org-epub-manifest)))))
           (unless (file-directory-p (expand-file-name "META-INF" org-epub-zip-dir))
             (make-directory (file-name-as-directory (expand-file-name "META-INF" org-epub-zip-dir))))
	   (with-current-buffer (find-file (expand-file-name "META-INF/container.xml" org-epub-zip-dir))
	     (erase-buffer)
	     (insert (org-epub-template-container))
	     (save-buffer 0)
	     (kill-buffer))
	   (with-current-buffer (find-file (concat org-epub-zip-dir "mimetype"))
	     (erase-buffer)
	     (insert (org-epub-template-mimetype))
	     ;; PKG-007: the mimetype file must contain *only* the string, with
	     ;; no trailing newline.
	     (let ((require-final-newline nil)
		   (mode-require-final-newline nil))
	       (save-buffer 0))
	     (kill-buffer))
	   (with-current-buffer (find-file (concat org-epub-zip-dir "body.html"))
	     (erase-buffer)
	     ;; EPUB3 content docs are parsed as XML under <!DOCTYPE html>; named
	     ;; HTML entities must become literal characters.
	     (insert (org-epub--xmlify body))
	     (save-buffer 0)
	     (kill-buffer)
	     (nconc org-epub-manifest (list (org-epub-manifest-entry "body-html" "body.html" 'html "application/xhtml+xml"))))
	   (with-current-buffer (find-file (concat org-epub-zip-dir "toc.ncx"))
	     (erase-buffer)
	     (insert
	      (org-epub-template-toc-ncx
	       (plist-get org-epub-metadata :epub-uid)
	       (plist-get org-epub-metadata :epub-toc-depth)
	       (plist-get org-epub-metadata :title)
	       (org-epub-generate-toc-single org-epub-headlines "body.html")))
	     (save-buffer 0)
	     (kill-buffer))
	   (with-current-buffer (find-file (concat org-epub-zip-dir "nav.xhtml"))
	     (erase-buffer)
	     (insert
	      (org-epub-template-nav
	       (plist-get org-epub-metadata :title)
	       (plist-get org-epub-metadata :language)
	       (org-epub-generate-nav-single org-epub-headlines "body.html")
	       (org-epub-manifest-first #'org-epub-cover-p)))
	     (save-buffer 0)
	     (kill-buffer)
	     (push (org-epub-manifest-entry "nav" "nav.xhtml" 'nav "application/xhtml+xml" nil "nav")
		   org-epub-manifest))
	   (with-current-buffer (find-file (concat org-epub-zip-dir "content.opf"))
	     (erase-buffer)
	     (insert (org-epub-template-content-opf
		      org-epub-metadata
		      (org-epub-gen-manifest org-epub-manifest)
		      (org-epub-gen-spine '(("body-html" . "body.html")))))
	     (save-buffer 0)
	     (kill-buffer))
	   (org-epub-zip-it-up outfile org-epub-manifest org-epub-zip-dir)
	   (delete-directory org-epub-zip-dir t)
	   (message (with-output-to-string (print org-epub-manifest)))
	   (message "Generated %s" outfile)
	   (expand-file-name outfile))
       (error (delete-directory org-epub-zip-dir t)
	      (message "ox-epub export error: %s" err)
	      ;; re-signal so headless/CI callers can detect the failure
	      ;; instead of receiving a success-looking return value.
	      (signal (car err) (cdr err))))))

;;compare org-export-options-alist
;;;###autoload
(defun org-epub-export-to-epub (&optional async subtreep visible-only ext-plist)
  "Export the current buffer to an EPUB file.

ASYNC defines wether this process should run in the background,
SUBTREEP supports narrowing of the document, VISIBLE-ONLY allows
you to export only visible parts of the document, EXT-PLIST is
the property list for the export process."
  (interactive)
  (let* ((outfile (org-export-output-file-name ".epub" subtreep)))
    (message "Output to:")
    (message outfile)
    (if async
	(org-export-async-start (lambda (f) (org-export-add-to-stack f 'odt))
	  (org-epub--export-wrapper
	   outfile
	   (org-export-as 'epub subtreep visible-only nil ext-plist)))
      (org-epub--export-wrapper
       outfile
       (org-export-as 'epub subtreep visible-only nil ext-plist)))))

(defun org-epub-template-toc-ncx (uid toc-depth title toc-nav)
  "Create the toc.ncx file.

UID is the uid/url of the file.  TOC-DEPTH is the depth of the toc
that should be shown to the readers.  TITLE is the title of the
ebook and TOC-NAV being the raw contents enclosed in navMap."
  (concat
   "<?xml version=\"1.0\"?>
<!DOCTYPE ncx PUBLIC \"-//NISO//DTD ncx 2005-1//EN\"
   \"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd\">

<ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\">

   <head>
      <meta name=\"dtb:uid\" content=\""
   (org-epub--xml-escape uid)
   "\"/>
      <meta name=\"dtb:depth\" content=\""
   (format "%d" toc-depth)
   "\"/>
      <meta name=\"dtb:totalPageCount\" content=\"0\"/>
      <meta name=\"dtb:maxPageNumber\" content=\"0\"/>
   </head>

   <docTitle>
      <text>"
   title
   "</text>
   </docTitle>

   <navMap>"
   toc-nav
   "</navMap>
</ncx>"))

(defun org-epub-template-content-opf (meta manifest spine)
  "Create the content.opf file.

META is a metadata PLIST.

The following arguments are XML strings: MANIFEST is the content
inside the manifest tags, this should include all user generated
html files but not things like the cover page, SPINE is an XML
string with the list of html files in reading order."
  (concat
   "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"dcidid\"
   version=\"3.0\">

   <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
      <dc:title>" (org-epub--xmlify (or (plist-get meta :title) "")) "</dc:title>
      <dc:language>" (or (org-string-nw-p (plist-get meta :language)) "en") "</dc:language>
      <dc:identifier id=\"dcidid\">" (org-epub--xml-escape (plist-get meta :epub-uid)) "</dc:identifier>
      <meta property=\"dcterms:modified\">" (org-epub--now-utc) "</meta>"
   (let ((s (org-string-nw-p (plist-get meta :epub-subject))))
     (when s (concat "\n      <dc:subject>" (org-epub--xmlify s) "</dc:subject>")))
   (let ((s (org-string-nw-p (plist-get meta :epub-description))))
     (when s (concat "\n      <dc:description>" (org-epub--xmlify s) "</dc:description>")))
   (let ((s (org-string-nw-p (plist-get meta :author))))
     (when s (concat "\n      <dc:creator>" (org-epub--xmlify s) "</dc:creator>")))
   (let ((s (org-string-nw-p (plist-get meta :epub-publisher))))
     (when s (concat "\n      <dc:publisher>" (org-epub--xmlify s) "</dc:publisher>")))
   (let ((s (org-string-nw-p (plist-get meta :date))))
     (when s (concat "\n      <dc:date>" s "</dc:date>")))
   (let ((s (org-string-nw-p (plist-get meta :epub-rights))))
     (when s (concat "\n      <dc:rights>" (org-epub--xmlify s) "</dc:rights>")))
   (let ((cimg (org-epub-manifest-first #'org-epub-coverimg-p)))
     (when cimg
       (concat "\n      <meta name=\"cover\" content=\"" (plist-get cimg :id) "\"/>")))
   "
   </metadata>

   <manifest>
      <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\" />
      "
   manifest
   "</manifest>

   <spine toc=\"ncx\">"
   (let ((chtml (org-epub-manifest-first #'org-epub-cover-p)))
     (when chtml
       (concat "<itemref idref=\"" (plist-get chtml :id) "\" linear=\"no\" />")))
   spine
   "</spine>"
   ;; EPUB3 navigation is the `landmarks' nav in nav.xhtml; the legacy
   ;; <guide> is emitted only for the cover (EPUB2 reader backward compat),
   ;; never empty (an empty <guide> is an RSC-005 error).
   (let ((chtml (org-epub-manifest-first #'org-epub-cover-p)))
     (when chtml
       (concat "\n\n <guide>\n  <reference type=\"cover\" title=\"Cover\" href=\""
	       (plist-get chtml :filename) "\" />\n </guide>")))
   "

</package>"))

(defun org-epub-gen-manifest (files)
  "Generate the manifest XML string.

FILES is the list of files to be included in the manifest xml string."
  (mapconcat
   (lambda (file)
     (let ((props (org-string-nw-p (plist-get file :properties))))
       (concat "<item id=\"" (plist-get file :id) "\" href=\"" (plist-get file :filename) "\""
	       " media-type=\"" (plist-get file :mimetype) "\""
	       (when props (concat " properties=\"" props "\""))
	       " />\n")))
   files ""))

(defun org-epub-gen-spine (files)
  "Generate the spine XML string.

FILES is the list of files to be included in the spine, these
must be in reading order."
  (mapconcat
   (lambda (file)
     (concat "<itemref idref=\"" (car file) "\" />\n"))
   files ""))

(defun org-epub-template-container ()
  "Generate the container.xml file, the root of any EPUB."
  "<?xml version=\"1.0\"?>
<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">
   <rootfiles>
      <rootfile full-path=\"content.opf\"
      media-type=\"application/oebps-package+xml\"/>
   </rootfiles>
</container>")

(defun org-epub-template-cover (cover-file width height &optional title)
  "Generate an XHTML template for the cover page.

COVER-FILE is the cover image filename, while WIDTH and HEIGHT are its
pixel dimensions.  TITLE, when given, is used as the page <title> (an
empty <title> is rejected by the EPUB3 schema)."
  (concat "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">
<head>
<title>" (org-epub--xmlify (or (org-string-nw-p title) "Cover")) "</title>
<meta charset=\"utf-8\" />
</head>
<body epub:type=\"cover\">
<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"
 width=\"100%\" height=\"100%\" viewBox=\"0 0 " (format "%d" width) " " (format "%d" height) "\" preserveAspectRatio=\"xMidYMid meet\">
<image xlink:href=\"" cover-file "\" height=\"" (format "%d" height) "\" width=\"" (format "%d" width) "\" />
</svg>
</body>
</html>"))

(defun org-epub-template-mimetype ()
  "Generate the mimetype file for the epub."
  "application/epub+zip")

(defun org-epub-zip-it-up (epub-file files target-dir)
  "Create the .epub file by zipping up the contents.

EPUB-FILE is the target filename, FILES is the list of source
files to process, while TARGET-DIR is the directory where
exported HTML files live. This function will copy any files into
their proper place."
  (mapc #'(lambda (entry)
	    (let ((copy (org-epub-manifest-needcopy entry)))
	      (when copy
		(copy-file (car copy) (concat target-dir (cdr copy)) t))))
	files)
  (let ((default-directory target-dir)
	(meta-files '("META-INF/container.xml" "content.opf" "toc.ncx")))
    (apply 'call-process
	   (append (list org-epub-zip-command nil '(:file "zip.log") nil)
		   org-epub-zip-no-compress
		   (list epub-file
			 "mimetype")))
    (apply 'call-process org-epub-zip-command nil '(:file "zip.log") nil
	   (append org-epub-zip-compress
		   (list epub-file)
		   (append meta-files (mapcar #'(lambda (el) (plist-get el :filename)) files)))))
  (copy-file (concat target-dir epub-file) default-directory t))

(defun org-epub-generate-toc-single (headlines filename)
  "Generate a single file TOC.

HEADLINES is a list containing the abbreviated headline
information. The name of the target file is given by FILENAME.
When there are no headlines a single fallback navPoint is emitted, since
an empty <navMap> is rejected by the NCX schema (RSC-005)."
  (if (null headlines)
      (format (concat "<navPoint class=\"h1\" id=\"%s-1\">\n"
		      "<navLabel><text>Start</text></navLabel>\n"
		      "<content src=\"%s\"/></navPoint>")
	      filename filename)
  (let ((toc-id 0)
	(current-level 0))
    (with-output-to-string
      (mapc
       (lambda (headline)
	 (let* ((title (nth 0 headline))
		(level (nth 1 headline))
		(ref (nth 2 headline)))
	   (cl-incf toc-id)
	   (cond
	    ((< current-level level)
	     (cl-incf current-level))
	    ((> current-level level)
	     (princ "</navPoint>")
	     (while (> current-level level)
	       (cl-decf current-level)
	       (princ "</navPoint>")))
	    ((eq current-level level)
	     (princ "</navPoint>")))
	   (princ
	    (concat (format "<navPoint class=\"h%d\" id=\"%s-%d\">\n" current-level filename toc-id)
		    (format "<navLabel><text>%s</text></navLabel>\n" (org-html-encode-plain-text title))
		    (format "<content src=\"%s#%s\"/>" filename ref)))))
       headlines)
      (while (> current-level 0)
	(princ "</navPoint>")
	(cl-decf current-level))))))

(defun org-epub-generate-nav-single (headlines filename)
  "Generate the nested <ol> body of an EPUB3 nav document.

HEADLINES is the abbreviated headline list ((TITLE LEVEL REF) ...).
FILENAME is the content document the references point into.  The nesting
mirrors `org-epub-generate-toc-single' so the ncx navMap and the nav
document stay structurally identical."
  (let ((current-level 0))
    (with-output-to-string
      (mapc
       (lambda (headline)
	 (let ((title (nth 0 headline))
	       (level (nth 1 headline))
	       (ref (nth 2 headline)))
	   (cond
	    ((< current-level level)
	     (princ "\n<ol>\n")
	     (cl-incf current-level))
	    ((> current-level level)
	     (princ "</li>\n")
	     (while (> current-level level)
	       (princ "</ol>\n</li>\n")
	       (cl-decf current-level)))
	    (t
	     (princ "</li>\n")))
	   (princ (format "<li><a href=\"%s#%s\">%s</a>"
			  filename ref (org-html-encode-plain-text title)))))
       headlines)
      (when (> current-level 0) (princ "</li>\n"))
      (while (> current-level 1)
	(princ "</ol>\n</li>\n")
	(cl-decf current-level))
      (when (>= current-level 1) (princ "</ol>")))))

(defun org-epub-template-nav (title lang nav-list cover-entry)
  "Create the EPUB3 navigation document (nav.xhtml).

TITLE is the book title, LANG its language, NAV-LIST the nested <ol>
table-of-contents body produced by `org-epub-generate-nav-single', and
COVER-ENTRY the cover manifest entry (or nil).  A `landmarks' nav is
emitted so the cover/start are reachable hyperlinks."
  (let ((title (org-epub--xmlify (or (org-string-nw-p title) "Table of Contents")))
	(lang (or (org-string-nw-p lang) "en"))
	(nav-list (if (org-string-nw-p nav-list)
		      nav-list
		    "<ol>\n<li><a href=\"body.html\">Start</a></li>\n</ol>")))
    (concat
     "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"" lang "\" xml:lang=\"" lang "\">
<head>
<title>" title "</title>
<meta charset=\"utf-8\" />
</head>
<body>
<nav epub:type=\"toc\" id=\"toc\">
<h1>" title "</h1>
" nav-list "
</nav>
<nav epub:type=\"landmarks\" id=\"landmarks\" hidden=\"hidden\">
<h2>Guide</h2>
<ol>
"
     (when cover-entry
       (concat "<li><a epub:type=\"cover\" href=\""
	       (plist-get cover-entry :filename) "\">Cover</a></li>\n"))
     "<li><a epub:type=\"bodymatter\" href=\"body.html\">Start</a></li>
</ol>
</nav>
</body>
</html>")))

(provide 'ox-epub)

;;; ox-epub.el ends here
