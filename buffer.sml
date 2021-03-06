signature BUFFER =
  sig
      type Buffer
      datatype BufferStatus = Complete | Incomplete | Errored | Dead
      val new : unit -> Buffer
      val newStatic : int -> Buffer
      val readInto : Buffer -> ('a,Socket.active Socket.stream) Socket.sock -> BufferStatus
      val toSlice : Buffer -> Word8ArraySlice.slice
  end 

structure DefaultBuffer : BUFFER =
  struct 
  type Buffer = { fill : int ref, buf : Word8Array.array ref, done_p: (int -> Word8Array.array -> bool)
		  , started : Time.time, tries : int ref}
  datatype BufferStatus = Complete | Incomplete | Errored | Dead
  local 
      val INIT_SIZE = 1000
      val MAX_SIZE = 50000
      val MAX_AGE = Time.fromSeconds 15
      val MAX_TRIES = 15

      fun done {fill, buf, done_p, started, tries} = done_p (!fill) (!buf)

      fun ageOf {fill, buf, done_p, started, tries} = Time.- (Time.now (), started)

      fun crlfx2 fill buf = 
	  let fun chk c i = (Word8.fromInt (Char.ord c)) = (Word8Array.sub (buf, fill - i))
	  in 
	      (fill >= 4) andalso (chk #"\r" 4) andalso (chk #"\n" 3) andalso (chk #"\r" 2) andalso (chk #"\n" 1)
	  end

      fun isFull {fill, buf, done_p, started, tries} = (Word8Array.length (!buf)) = (!fill)

      fun grow {fill, buf, done_p, started, tries} = 
	  let val len = Word8Array.length (!buf)
	      val newBuf = Word8Array.array (len * 2, Word8.fromInt 0)
	  in 
	      Word8Array.copy {di=0, dst=newBuf, src=(!buf)};
	      buf := newBuf;
	      ()
	  end
  in 

  fun readInto buffer sock = 
      let val {fill, buf, done_p, started, tries} = buffer
	  fun recur () =
	      let val i = Socket.recvArrNB (sock, Word8ArraySlice.slice (!buf, !fill, SOME 1))
	      in 
		  if i = NONE then () else (fill := (!fill + 1));
		  if done buffer
		  then Complete
		  else if (!fill > MAX_SIZE) orelse (Time.> (ageOf buffer, MAX_AGE)) orelse (!tries > MAX_TRIES)
		  then Errored
		  else case i of
			   NONE => Incomplete
			 | SOME n => (if isFull buffer then grow buffer else ();
				      recur ())
	      end
      in 
	  tries := (!tries + 1);
	  recur ()
      end
      handle _ => Dead

  fun newStatic size =
      let fun done f b = f = (Word8Array.length b)
      in
	  { fill= ref 0, buf= ref (Word8Array.array (size, Word8.fromInt 0)), done_p= done,
	    started= Time.now (), tries = ref 0}
      end

  fun new () = 
      { fill= ref 0, buf= ref (Word8Array.array (INIT_SIZE, Word8.fromInt 0)), done_p=crlfx2,
	started= Time.now (), tries = ref 0}

  fun toSlice {fill, buf, done_p, started, tries} = Word8ArraySlice.slice (!buf, 0, SOME (!fill))
  end
end
