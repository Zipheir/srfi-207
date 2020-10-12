;;; Copyright (C) 2020 Wolfgang Corcoran-Mathe
;;;
;;; Permission is hereby granted, free of charge, to any person obtaining a
;;; copy of this software and associated documentation files (the
;;; "Software"), to deal in the Software without restriction, including
;;; without limitation the rights to use, copy, modify, merge, publish,
;;; distribute, sublicense, and/or sell copies of the Software, and to
;;; permit persons to whom the Software is furnished to do so, subject to
;;; the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be included
;;; in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
;;; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;;; IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;;; CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;;; TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

(import (scheme base))
(import (srfi 207))
(import (only (srfi 1) list-tabulate every)
        (only (srfi 158) generator->list))

(cond-expand
  ((library (srfi 78))
   (import (srfi 78)))
  (else
    (begin
      (define *tests-failed* 0)
      (define-syntax check
        (syntax-rules (=>)
          ((check expr => expected)
           (if (equal? expr expected)
             (begin
               (display 'expr)
               (display " => ")
               (display expected)
               (display " ; correct")
               (newline))
             (begin
               (set! *tests-failed* (+ *tests-failed* 1))
               (display "FAILED: for ")
               (display 'expr)
               (display " expected ")
               (display expected)
               (display " but got ")
               (display expr)
               (newline))))))
      (define (check-report)
        (if (zero? *tests-failed*)
            (begin
             (display "All tests passed.")
             (newline))
            (begin
             (display "TESTS FAILED: ")
             (display *tests-failed*)
             (newline)))))))

;;;; Utility

(define (print-header message)
  (newline)
  (display (string-append ";;; " message))
  (newline))

(define-syntax constantly
  (syntax-rules ()
    ((_ obj) (lambda _ obj))))

(define always (constantly #t))
(define never (constantly #f))

;; Returns a list of the values produced by expr.
(define-syntax values~>list
  (syntax-rules ()
    ((_ expr)
     (call-with-values (lambda () expr) list))))

;; If expr causes an exception to be raised, return 'bytestring-error
;; if the raised object satisfies bytestring-error?, and #f otherwise.
(define-syntax catch-bytestring-error
  (syntax-rules ()
   ((_ expr)
    (guard (condition ((bytestring-error? condition) 'bytestring-error)
                      (else #f))
      expr))))

(define-syntax with-output-to-bytevector
  (syntax-rules ()
    ((_ thunk)
     (parameterize ((current-output-port (open-output-bytevector)))
       (thunk)
       (get-output-bytevector (current-output-port))))))

;; Testing shorthands for SNB I/O.  Coverage library fans, eat your
;; hearts out.
(define (parse-SNB s)
  (call-with-port (open-input-string s) read-textual-bytestring))

(define (%bytestring->SNB bstring)
  (call-with-port (open-output-string)
                  (lambda (port)
		    (write-textual-bytestring bstring port)
		    (get-output-string port))))


(define test-bstring (bytestring "lorem"))

(define homer
  (bytestring "The Man, O Muse, informe, who many a way / \
               Wound in his wisedome to his wished stay;"))

(define homer64
  "VGhlIE1hbiwgTyBNdXNlLCBpbmZvcm1lLCB3aG8gbWFueSBhIHdheSAvIFdvd\
   W5kIGluIGhpcyB3aXNlZG9tZSB0byBoaXMgd2lzaGVkIHN0YXk7")

(define homer64-w
  "VGhlIE1hb iwgTyBNdXNlL CBpbmZvcm1lL\nCB3aG8gbWF\tueSBhIH\rdheSAvIFdvd\
   W5kIGluI   GhpcyB    3aXNlZ\t\t\nG9tZSB0b    yBoaXMgd\t2lzaGVkIHN0YXk7")

;;;; Constructors

(define (check-constructor)
  (print-header "Running constructor tests...")
  (check (bytestring "lo" #\r #x65 #u8(#x6d)) => test-bstring)
  (check (bytestring)                         => (bytevector))

  (check (catch-bytestring-error (bytestring #x100)) => 'bytestring-error)
  (check (catch-bytestring-error (bytestring "λ"))   => 'bytestring-error))

(define (check-conversion)
  (print-header "Running conversion tests...")

  (check (bytestring->hex-string test-bstring) => "6c6f72656d")
  (check (hex-string->bytestring "6c6f72656d") => test-bstring)
  (check (catch-bytestring-error
          (hex-string->bytestring "c6f72656d"))
   => 'bytestring-error)
  (check (catch-bytestring-error
          (hex-string->bytestring "6czf72656d"))
   => 'bytestring-error)
  (check (equal? (hex-string->bytestring (bytestring->hex-string homer))
                 homer)
   => #t)

  (check (hex-string->bytestring (bytestring->hex-string #u8())) => #u8())

  (check (bytestring->base64 test-bstring)             => "bG9yZW0=")
  (check (bytestring->base64 #u8(#xff #xef #xff))      => "/+//")
  (check (bytestring->base64 #u8(#xff #xef #xff) "*@") => "@*@@")
  (check (equal? (bytestring->base64 homer) homer64)   => #t)
  (check (bytestring->base64 #u8(1))                   => "AQ==")
  (check (bytestring->base64 #u8())                    => "")
  (check (base64->bytestring "bG9yZW0=")               => test-bstring)
  (check (base64->bytestring "/+//")                   => #u8(#xff #xef #xff))
  (check (base64->bytestring "@*@@" "*@")              => #u8(#xff #xef #xff))
  (check (equal? (base64->bytestring homer64) homer)   => #t)
  (check (equal? (base64->bytestring homer64-w) homer) => #t)
  (check (base64->bytestring "AQ==")                   => #u8(1))
  (check (base64->bytestring "")                       => #u8())
  (check (base64->bytestring "\n\n\n==\t\r\n")         => #u8())
  (check (catch-bytestring-error
          (base64->bytestring "bG9@frob"))             => 'bytestring-error)

  (check (bytestring->list #u8()) => '())
  (check (bytestring->list test-bstring) => '(#x6c #x6f #x72 #x65 #x6d))
  (check (list->bytestring (bytestring->list test-bstring)) => test-bstring)

  (let ((bvec (make-bytevector 5)))
    (check (begin
            (list->bytestring! bvec 0 '(#x6c #x6f #x72 #x65 #x6d))
            bvec)
     => test-bstring))
  (let ((bvec (make-bytevector 9 #x20)))
    (check (begin (list->bytestring! bvec 2 '("lo" #\r #x65 #u8(#x6d)))
                  bvec)
     => (bytestring "  lorem  ")))

  (let ((s (list-tabulate (bytevector-length test-bstring)
                          (lambda (i)
                            (bytevector-u8-ref test-bstring i)))))
    (check (let ((g (make-bytestring-generator "lo" #\r #x65 #u8(#x6d))))
             (generator->list g))
     => s))
)

(define (check-selection)
  (print-header "Running selection tests...")

  (check (bytestring-pad test-bstring (bytevector-length test-bstring) #x7a)
   => test-bstring)
  (check (utf8->string (bytestring-pad test-bstring 8 #x7a))
   => "zzzlorem")
  (check (equal? (bytestring-pad test-bstring 8 #\z)
                 (bytestring-pad test-bstring 8 (char->integer #\z)))
   => #t)
  (check (bytestring-pad-right test-bstring
                               (bytevector-length test-bstring)
                               #x7a)
   => test-bstring)
  (check (utf8->string (bytestring-pad-right test-bstring 8 #x7a))
   => "loremzzz")
  (check (equal? (bytestring-pad-right test-bstring 8 #\z)
                 (bytestring-pad-right test-bstring 8 (char->integer #\z)))
   => #t)

  (check (bytestring-trim test-bstring always) => #u8())
  (check (bytestring-trim test-bstring never)  => test-bstring)
  (check (bytestring-trim test-bstring (lambda (u8) (< u8 #x70)))
   => #u8(#x72 #x65 #x6d))
  (check (bytestring-trim-right test-bstring always) => #u8())
  (check (bytestring-trim-right test-bstring never)  => test-bstring)
  (check (bytestring-trim-right test-bstring (lambda (u8) (< u8 #x70)))
   => #u8(#x6c #x6f #x72))
  (check (bytestring-trim-both test-bstring always) => #u8())
  (check (bytestring-trim-both test-bstring never)  => test-bstring)
  (check (bytestring-trim-both test-bstring (lambda (u8) (< u8 #x70)))
   => #u8(#x72)))

(define (check-replacement)
  (print-header "Running bytestring-replace tests...")

  (check (bytestring-replace test-bstring (bytestring "mists") 1 5)
   => (bytestring "lists"))
  (check (bytestring-replace test-bstring (bytestring "faded") 2 5 1 5)
   => (bytestring "loaded"))
  (check (bytestring-replace (make-bytevector 5)
                             test-bstring
                             0
                             (bytevector-length test-bstring))
   => test-bstring)

  ;; Replacing from the end of the `to' bytestring is equivalent
  ;; to appending the two bytestrings.
  (let ((test-bstring2 (bytestring " ipsum")))
    (check (bytestring-replace test-bstring
                               test-bstring2
                               (bytevector-length test-bstring)
                               (bytevector-length test-bstring)
                               0
                               (bytevector-length test-bstring2))
     => (bytevector-append test-bstring test-bstring2))))

(define (check-comparison)
  (define short-bstring (bytestring "lore"))
  (define long-bstring (bytestring "lorem "))
  (define mixed-case-bstring (bytestring "loreM"))
  (print-header "Runnng comparison tests...")

  (check (bytestring<? test-bstring test-bstring)        => #f)
  (check (bytestring<? short-bstring test-bstring)       => #t)
  (check (bytestring<? mixed-case-bstring test-bstring)  => #t)
  (check (bytestring>? test-bstring test-bstring)        => #f)
  (check (bytestring>? test-bstring short-bstring)       => #t)
  (check (bytestring>? test-bstring mixed-case-bstring)  => #t)
  (check (bytestring<=? test-bstring test-bstring)       => #t)
  (check (bytestring<=? short-bstring test-bstring)      => #t)
  (check (bytestring<=? mixed-case-bstring test-bstring) => #t)
  (check (bytestring<=? test-bstring mixed-case-bstring) => #f)
  (check (bytestring<=? long-bstring test-bstring)       => #f)
  (check (bytestring>=? test-bstring test-bstring)       => #t)
  (check (bytestring>=? test-bstring short-bstring)      => #t)
  (check (bytestring>=? test-bstring mixed-case-bstring) => #t)
  (check (bytestring>=? mixed-case-bstring test-bstring) => #f)
  (check (bytestring>=? short-bstring test-bstring)      => #f)

  (check (bytestring-ci=? test-bstring test-bstring)        => #t)
  (check (bytestring-ci=? test-bstring
                          #u8(#x6c #x6f #x72 #x65 #x6d))
   => #t)
  (check (bytestring-ci=? test-bstring mixed-case-bstring)  => #t)
  (check (bytestring-ci=? test-bstring short-bstring)       => #f)
  (check (bytestring-ci<? test-bstring test-bstring)        => #f)
  (check (bytestring-ci<? short-bstring test-bstring)       => #t)
  (check (bytestring-ci<? mixed-case-bstring test-bstring)  => #f)
  (check (bytestring-ci>? test-bstring test-bstring)        => #f)
  (check (bytestring-ci>? test-bstring short-bstring)       => #t)
  (check (bytestring-ci>? test-bstring mixed-case-bstring)  => #f)
  (check (bytestring-ci<=? test-bstring test-bstring)       => #t)
  (check (bytestring-ci<=? short-bstring test-bstring)      => #t)
  (check (bytestring-ci<=? mixed-case-bstring test-bstring) => #t)
  (check (bytestring-ci<=? test-bstring mixed-case-bstring) => #t)
  (check (bytestring-ci<=? long-bstring test-bstring)       => #f)
  (check (bytestring-ci>=? test-bstring test-bstring)       => #t)
  (check (bytestring-ci>=? test-bstring short-bstring)      => #t)
  (check (bytestring-ci>=? test-bstring mixed-case-bstring) => #t)
  (check (bytestring-ci>=? mixed-case-bstring test-bstring) => #t)
  (check (bytestring-ci>=? short-bstring test-bstring)      => #f))

(define (check-searching)
  (define (eq-r? b) (= b #x72))
  (define (lt-r? b) (< b #x72))
  (print-header "Running search tests...")

  (check (bytestring-index test-bstring always)     => 0)
  (check (bytestring-index test-bstring never)      => #f)
  (check (bytestring-index test-bstring always 3)   => 3)
  (check (bytestring-index test-bstring eq-r?) => 2)

  (check (bytestring-index-right test-bstring always)     => 4)
  (check (bytestring-index-right test-bstring never)      => #f)
  (check (bytestring-index-right test-bstring always 3)   => 4)
  (check (bytestring-index-right test-bstring eq-r?) => 2)

  (check (values~>list (bytestring-span test-bstring always))
   => (list test-bstring (bytevector)))
  (check (values~>list (bytestring-span test-bstring never))
   => (list (bytevector) test-bstring))
  (check (values~>list (bytestring-span test-bstring lt-r?))
   => (list (bytestring "lo") (bytestring "rem")))

  (check (values~>list (bytestring-break test-bstring always))
   => (list (bytevector) test-bstring))
  (check (values~>list (bytestring-break test-bstring never))
   => (list test-bstring (bytevector)))
  (check (values~>list (bytestring-break test-bstring eq-r?))
   => (list (bytestring "lo") (bytestring "rem"))))

(define (check-join-and-split)
  (define test-segments '(#u8(1) #u8(2) #u8(3)))
  (print-header "Running joining and splitting tests...")

  (check (bytestring-join test-segments #u8(0))         => #u8(1 0 2 0 3))
  (check (bytestring-join test-segments #u8(0) 'prefix) => #u8(0 1 0 2 0 3))
  (check (bytestring-join test-segments #u8(0) 'suffix) => #u8(1 0 2 0 3 0))
  (check (bytestring-join '() #u8(0))                   => #u8())
  (check (catch-bytestring-error
           (bytestring-join '() #u8(0) 'strict-infix))  => 'bytestring-error)
  (check (catch-bytestring-error
           (bytestring-join '() #u8(0) 'foofix))        => 'bytestring-error)

  (check (bytestring-split #u8(1 0 2 0 3) 0 'infix)    => test-segments)
  (check (bytestring-split #u8(0 1 0 2 0 3) 0 'prefix) => test-segments)
  (check (bytestring-split #u8(1 0 2 0 3 0) 0 'suffix) => test-segments)
  (check (bytestring-split #u8(0 0) 0)                 => '(#u8() #u8() #u8()))
  (check (bytestring-split #u8() 0)                    => '())
  (check (catch-bytestring-error
           (bytestring-split #u8() 0 'foofix))         => 'bytestring-error))

(define (check-io)
  (print-header "Running I/O tests...")

  (check
   (with-output-to-bytevector
    (lambda ()
      (write-binary-bytestring (current-output-port) "lo" #\r #x65 #u8(#x6d))))
   => test-bstring)
  (check
   (catch-bytestring-error
    (with-output-to-bytevector
     (lambda () (write-binary-bytestring (current-output-port) #x100))))
   => 'bytestring-error)

  ;;; read-textual-bytestring

  (check (parse-SNB "#u8\"lorem\"") => test-bstring)
  (check (parse-SNB "#u8\"\\xde;\\xad;\\xf0;\\x0d;\"")
   => (bytevector #xde #xad #xf0 #x0d))
  (check (parse-SNB "#u8\"\\\"\\\\\\a\\b\\t\\n\\r\"")
   => (bytestring #\" #\\ #\alarm #\backspace #\tab #\newline #\return))
  (check (parse-SNB "#u8\"lor\\\n\te\\   \r\n\tm\"")
   => test-bstring)

  ;; Invalid SNB detection.
  (check (catch-bytestring-error (parse-SNB "#u\"lorem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8lorem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"lorem"))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"lorem"))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"l\\orem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"l\\    orem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"l\\x6frem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"l\\x6z;rem\""))
   => 'bytestring-error)
  (check (catch-bytestring-error (parse-SNB "#u8\"α equivalence\""))
   => 'bytestring-error)

  ;;; write-textual-bytestring

  (check (%bytestring->SNB test-bstring) => "#u8\"lorem\"")
  (check (%bytestring->SNB (bytevector #xde #xad #xbe #xef))
   => "#u8\"\\xde;\\xad;\\xbe;\\xef;\"")
  (check (%bytestring->SNB
          (bytestring #\" #\\ #\alarm #\backspace #\tab #\newline #\return))
   => "#u8\"\\\"\\\\\\a\\b\\t\\n\\r\"")

  (let ((test-bstrings
         '(#u8(124 199 173 212 209 232 249 16 198 32 123 111 130 92 64 155)
           #u8(50 133 193 27 177 105 10 186 61 149 177 105 96 70 223 190)
           #u8(0 117 226 155 110 0 66 216 27 129 187 81 17 210 71 152)
           #u8(123 31 159 25 100 135 246 47 249 137 243 241 45 241 240 221)
           #u8(207 186 70 110 118 231 79 195 153 253 93 101 126 198 70 235)
           #u8(138 176 92 152 208 107 28 236 198 254 111 37 241 116 191 206)
           #u8(221 254 214 90 0 155 132 92 157 246 199 224 224 142 91 114)
           #u8(228 216 233 80 142 15 158 54 5 85 174 101 111 75 126 209)
           #u8(191 16 83 245 45 98 72 212 148 202 135 19 213 150 141 121)
           #u8(41 169 182 96 47 184 16 116 196 251 243 93 81 162 175 140)
           #u8(85 49 218 138 132 11 27 11 182 27 120 71 254 169 132 166)
           #u8(89 216 175 23 97 10 237 112 208 195 112 80 198 154 241 254)
           #u8(187 54 6 57 250 137 129 89 188 19 225 217 168 178 174 129)
           #u8(88 164 89 40 175 194 108 56 12 124 109 96 148 149 119 109)
           #u8(241 66 32 115 203 71 128 154 240 111 194 137 73 44 146 3)
           #u8(177 185 177 233 18 14 178 106 110 109 222 147 111 157 216 208))))
    (check
     (every (lambda (bvec)
              (equal? bvec (parse-SNB (%bytestring->SNB bvec))))
            test-bstrings)
    => #t))
)

(define (check-all)
  (check-constructor)
  (check-conversion)
  (check-selection)
  (check-replacement)
  (check-comparison)
  (check-searching)
  (check-join-and-split)
  (check-io)

  (newline)
  (check-report))

;(check-all)
