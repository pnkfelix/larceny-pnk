; Copyright 1998 Lars T Hansen.
;
; $Id$
;
; Larceny -- I/O system.
;
; Design: the system is designed so that in the common case, very few
; procedure calls are executed.

($$trace "iosys")

; NOTE that you can *not* change these values without also changing them
; in io/read-char, below, where they have been in-lined.

(define port.input?     0) ; boolean: an open input port
(define port.output?    1) ; boolean: an open output port
(define port.iodata     2) ; port-specific data
(define port.ioproc     3) ; port*symbol -> void
(define port.buffer     4) ; a string or #f: i/o buffer
(define port.error?     5) ; boolean: #t after error

; input ports

(define port.rd-eof?    6) ; boolean: input port at EOF
(define port.rd-lim     7) ; nonnegative fixnum: index beyond last char
(define port.rd-ptr     8) ; nonnegative fixnum: next loc for input

; output ports

(define port.wr-flush?  9) ; boolean: discretionary output flushing
(define port.wr-ptr    10) ; nonnegative fixnum: next loc for output

; common data

(define port.position  11) ; nonnegative fixnum: number of characters read
                           ; or written, not counting what's in the current
                           ; buffer.

(define port.structure-size 12)      ; size of port structure
(define port.buffer-size    1024)    ; length of default I/O buffer


;;; Private procedures

(define (io/fill-buffer p)
  (vector-like-set! p port.position 
                    (+ (vector-like-ref p port.position)
                       (vector-like-ref p port.rd-ptr)))
  (let ((r (((vector-like-ref p port.ioproc) 'read)
            (vector-like-ref p port.iodata)
            (vector-like-ref p port.buffer))))
    (cond ((eq? r 'eof)
           (vector-like-set! p port.rd-ptr 0)
           (vector-like-set! p port.rd-lim 0)
           (vector-like-set! p port.rd-eof? #t))
          ((eq? r 'error)
           (vector-like-set! p port.error? #t)
           (error "Read error on port " p)
           #t)
          ((and (fixnum? r) (>= r 0))
           (vector-like-set! p port.rd-ptr 0)
           (vector-like-set! p port.rd-lim r))
          (else
           (vector-like-set! p port.error? #t)
           (error "io/fill-buffer: bad value " r " on " p)))))

(define (io/flush-buffer p)
  (let ((wr-ptr (vector-like-ref p port.wr-ptr)))
    (if (> wr-ptr 0)
        (let ((r (((vector-like-ref p port.ioproc) 'write)
                  (vector-like-ref p port.iodata)
                  (vector-like-ref p port.buffer)
                  wr-ptr)))
          (vector-like-set! p port.position
                            (+ (vector-like-ref p port.position) wr-ptr))
          (cond ((eq? r 'ok)
                 (vector-like-set! p port.wr-ptr 0))
                ((eq? r 'error)
                 (vector-like-set! p port.error? #t)
                 (error "Write error on port " p)
                 #t)
                (else
                 (vector-like-set! p port.error? #t)
                 (error "io/flush-buffer: bad value " r " on " p)
                 #t))))))


;;; Public low-level interface

(define (io/initialize)
  ; Nothing, for the time being.
  #t)

; 'ioproc' is a procedure of one argument: a symbol that denotes the 
; operation to perform.  It returns a port-specific procedure that, when
; called, performs the operation.  The operations are:
;
;   read : iodata * buffer -> { fixnum, 'eof, 'error }
;   write : iodata * buffer * count -> { 'ok, 'error }
;   close : iodata -> { 'ok, 'error }
;   ready? : iodata -> boolean
;   name : iodata -> string

(define (io/make-port ioproc iodata . rest)
  (let ((v (make-vector port.structure-size #f)))
    (do ((l rest (cdr l)))
        ((null? l))
      (case (car l)
        ((input)   (vector-set! v port.input? #t))
        ((output)  (vector-set! v port.output? #t))
        ((text)    #t)  ; nothing yet
        ((binary)  #t)  ; nothing yet
        ((flush)   (vector-set! v port.wr-flush? #t))
        (else      (error "make-port: bad attribute: " (car l))
                   #t)))
    (vector-set! v port.ioproc ioproc)
    (vector-set! v port.iodata iodata)
    (vector-set! v port.buffer (make-string port.buffer-size))
    (vector-set! v port.rd-lim 0)
    (vector-set! v port.rd-ptr 0)
    (vector-set! v port.wr-ptr 0)
    (vector-set! v port.position 0)
    (typetag-set! v sys$tag.port-typetag)
    v))

; Port? is integrable.
; Eof-object? is integrable.

(define (io/input-port? p)
  (and (port? p) (vector-like-ref p port.input?)))

(define (io/output-port? p)
  (and (port? p) (vector-like-ref p port.output?)))

(define (io/open-port? p)
  (or (io/input-port? p) (io/output-port? p)))

; Moving the constants in-line improves performance because the global
; variable references are heavyweight -- several loads, and a check for
; definedness.

(define (io/read-char p)
  (if (and (port? p) (vector-like-ref p 0))          ; 0 = port.input?
      (let ((ptr (vector-like-ref p 8))              ; 8 = port.rd-ptr
            (lim (vector-like-ref p 7))              ; 7 = port.rd-lim
            (buf (vector-like-ref p 4)))             ; 4 = port.buffer
        (cond ((< ptr lim)
               (let ((c (string-ref buf ptr)))
                 (vector-like-set! p 8 (+ ptr 1))    ; 8 = port.rd-ptr
                 c))
              ((vector-like-ref p 6)                 ; 6 = port.rd-eof?
               (eof-object))
              (else
               (io/fill-buffer p)
               (io/read-char p))))
      (begin (error "read-char: not an input port: " p)
             #t)))

(define (io/peek-char p)
  (if (and (port? p) (vector-like-ref p port.input?))
      (let ((ptr (vector-like-ref p port.rd-ptr))
            (lim (vector-like-ref p port.rd-lim))
            (buf (vector-like-ref p port.buffer)))
        (cond ((< ptr lim)
               (string-ref buf ptr))
              ((vector-like-ref p port.rd-eof?)
               (eof-object))
              (else
               (io/fill-buffer p)
               (io/peek-char p))))
      (begin (error "peek-char: not an input port: " p)
             #t)))

; This is a hack that speeds up the current reader.
; peek-next-char discards the current character and peeks the next one.

(define (io/peek-next-char p)
  (if (and (port? p) (vector-like-ref p port.input?))
      (let ((ptr (vector-like-ref p port.rd-ptr))
            (lim (vector-like-ref p port.rd-lim))
            (buf (vector-like-ref p port.buffer)))
        (cond ((< ptr lim)
               (let ((ptr (+ ptr 1)))
                 (vector-like-set! p port.rd-ptr ptr)
                 (if (< ptr lim)
                     (string-ref buf ptr)
                     (io/peek-char p))))
              ((vector-like-ref p port.rd-eof?)
               (eof-object))
              (else
               (io/fill-buffer p)
               (io/peek-char p))))
      (begin (error "peek-next-char: not an input port: " p)
             #t)))

(define (io/char-ready? p)
  (if (and (port? p) (vector-like-ref p port.input?))
      (cond ((< (vector-like-ref p port.rd-ptr)
                (vector-like-ref p port.rd-lim))
             #t)
            ((vector-like-ref p port.rd-eof?)
             #t)
            (else
             (((vector-like-ref p port.ioproc) 'ready?)
              (vector-like-ref p port.iodata))))
      (begin (error "io/char-ready?: not an input port: " p)
             #t)))

(define (io/write-char c p)
  (if (and (port? p) (vector-like-ref p port.output?))
      (let ((buf (vector-like-ref p port.buffer))
            (ptr (vector-like-ref p port.wr-ptr)))
        (cond ((< ptr (string-length buf))
               (string-set! buf ptr c)
               (vector-like-set! p port.wr-ptr (+ ptr 1))
               (unspecified))
              (else
               (io/flush-buffer p)
               (io/write-char c p))))
      (begin (error "write-char: not an output port: " p)
             #t)))

; This is _not_ clean, but other parts of the I/O system may currently
; depend on a string (rather than bytevector-like) buffer.  This should
; be checked, and fixed.  FIXME.
;
; Also, for short strings, it might be more effective to copy rather than
; flush.  This procedure is really most useful for long strings, and was
; written to speed up fasl file writing.

(define (io/write-bytevector-like bvl p)
  (if (and (port? p) (vector-like-ref p port.output?))
      (let ((buf (vector-like-ref p port.buffer))
            (tt  (typetag bvl)))
        (io/flush-buffer p)
        (vector-like-set! p port.buffer bvl)
        (vector-like-set! p port.wr-ptr (bytevector-like-length bvl))
        (typetag-set! bvl sys$tag.string-typetag)
        (io/flush-buffer p)
        (typetag-set! bvl tt)
        (vector-like-set! p port.buffer buf)
        (vector-like-set! p port.wr-ptr 0)
        (unspecified))
      (begin (error "io/write-bytevector-like: not an output port: " p)
             #t)))
  
(define (io/discretionary-flush p)
  (if (and (port? p) (vector-like-ref p port.output?))
      (if (vector-like-ref p port.wr-flush?)
          (io/flush-buffer p))
      (begin (error "io/discretionary-flush: not an output port: " p)
             #t)))

(define (io/flush p)
  (if (and (port? p) (vector-like-ref p port.output?))
      (io/flush-buffer p)
      (begin (error "io/flush: not an output port: " p)
             #t)))

(define (io/close-port p)
  (if (port? p)
      (begin
        (if (vector-like-ref p port.output?)
            (io/flush-buffer p))
        (((vector-like-ref p port.ioproc) 'close)
         (vector-like-ref p port.iodata))
        (vector-like-set! p port.input? #f)
        (vector-like-set! p port.output? #f)
        (unspecified))
      (begin (error "io/close-port: not a port: " p)
             #t)))

(define (io/port-name p)
  (((vector-like-ref p port.ioproc) 'name) (vector-like-ref p port.iodata)))

(define (io/port-error-condition? p)
  (vector-like-ref p port.error?))

(define (io/port-at-eof? p)
  (vector-like-ref p port.rd-eof?))

(define (io/port-position p)
  (cond ((io/input-port? p)
         (+ (vector-like-ref p port.position)
            (vector-like-ref p port.rd-ptr)))
        ((io/output-port? p)
         (+ (vector-like-ref p port.position)
            (vector-like-ref p port.wr-ptr)))
        (else
         (error "io/port-position: " p " is not an open port.")
         #t)))

; eof