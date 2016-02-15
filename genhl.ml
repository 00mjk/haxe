(*
 * Copyright (C)2005-2015 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *)
open Unix
open Ast
open Type
open Common

type reg = int
type global = int
type 'a index = int
type functable

type ttype =
	| HVoid
	| HI8
	| HI16
	| HI32
	| HF32
	| HF64
	| HBool
	| HBytes
	| HDyn
	| HFun of ttype list * ttype
	| HObj of class_proto
	| HArray
	| HType
	| HRef of ttype
	| HVirtual of virtual_proto
	| HDynObj
	| HAbstract of string * string index
	| HEnum of enum_proto
	| HNull of ttype

and class_proto = {
	pname : string;
	pid : int;
	mutable pclassglobal : int option;
	mutable psuper : class_proto option;
	mutable pvirtuals : int array;
	mutable pproto : field_proto array;
	mutable pnfields : int;
	mutable pfields : (string * string index * ttype) array;
	mutable pindex : (string, int * ttype) PMap.t;
	mutable pfunctions : (string, int) PMap.t;
}

and enum_proto = {
	ename : string;
	eid : int;
	mutable eglobal : int;
	mutable efields : (string * string index * ttype array) array;
}

and field_proto = {
	fname : string;
	fid : int;
	fmethod : functable index;
	fvirtual : int option;
}

and virtual_proto = {
	mutable vfields : (string * string index * ttype) array;
	mutable vindex : (string, int) PMap.t;
}

type unused = int
type field

type opcode =
	| OMov of reg * reg
	| OInt of reg * int index
	| OFloat of reg * float index
	| OBool of reg * bool
	| OBytes of reg * string index
	| OString of reg * string index
	| ONull of reg
	| OAdd of reg * reg * reg
	| OSub of reg * reg * reg
	| OMul of reg * reg * reg
	| OSDiv of reg * reg * reg
	| OUDiv of reg * reg * reg
	| OSMod of reg * reg * reg
	| OUMod of reg * reg * reg
	| OShl of reg * reg * reg
	| OSShr of reg * reg * reg
	| OUShr of reg * reg * reg
	| OAnd of reg * reg * reg
	| OOr of reg * reg * reg
	| OXor of reg * reg * reg
	| ONeg of reg * reg
	| ONot of reg * reg
	| OIncr of reg
	| ODecr of reg
	| OCall0 of reg * functable index
	| OCall1 of reg * functable index * reg
	| OCall2 of reg * functable index * reg * reg
	| OCall3 of reg * functable index * reg * reg * reg
	| OCall4 of reg * functable index * reg * reg * reg * reg
	| OCallN of reg * functable index * reg list
	| OCallMethod of reg * field index * reg list
	| OCallThis of reg * field index * reg list
	| OCallClosure of reg * reg * reg list
	| OGetFunction of reg * functable index (* closure *)
	| OClosure of reg * functable index * reg (* closure *)
	| OGetGlobal of reg * global
	| OSetGlobal of global * reg
	| ORet of reg
	| OJTrue of reg * int
	| OJFalse of reg * int
	| OJNull of reg * int
	| OJNotNull of reg * int
	| OJSLt of reg * reg * int
	| OJSGte of reg * reg * int
	| OJSGt of reg * reg * int
	| OJSLte of reg * reg * int
	| OJULt of reg * reg * int
	| OJUGte of reg * reg * int
	| OJEq of reg * reg * int
	| OJNotEq of reg * reg * int
	| OJAlways of int
	| OToDyn of reg * reg
	| OToSFloat of reg * reg
	| OToUFloat of reg * reg
	| OToInt of reg * reg
	| OLabel of unused
	| ONew of reg
	| OField of reg * reg * field index
	| OMethod of reg * reg * field index (* closure *)
	| OSetField of reg * field index * reg
	| OGetThis of reg * field index
	| OSetThis of field index * reg
	| OThrow of reg
	| ORethrow of reg
	| OGetI8 of reg * reg * reg
	| OGetI32 of reg * reg * reg
	| OGetF32 of reg * reg * reg
	| OGetF64 of reg * reg * reg
	| OGetArray of reg * reg * reg
	| OSetI8 of reg * reg * reg
	| OSetI32 of reg * reg * reg
	| OSetF32 of reg * reg * reg
	| OSetF64 of reg * reg * reg
	| OSetArray of reg * reg * reg
	| OSafeCast of reg * reg
	| OUnsafeCast of reg * reg
	| OArraySize of reg * reg
	| OError of string index
	| OType of reg * ttype
	| OGetType of reg * reg
	| OGetTID of reg * reg
	| ORef of reg * reg
	| OUnref of reg * reg
	| OSetref of reg * reg
	| OToVirtual of reg * reg
	| OUnVirtual of reg * reg
	| ODynGet of reg * reg * string index
	| ODynSet of reg * string index * reg
	| OMakeEnum of reg * field index * reg list
	| OEnumAlloc of reg * field index
	| OEnumIndex of reg * reg
	| OEnumField of reg * reg * field index * int
	| OSetEnumField of reg * int * reg
	| OSwitch of reg * int array
	| ONullCheck of reg
	| OTrap of reg * int
	| OEndTrap of unused
	| ODump of reg

type fundecl = {
	findex : functable index;
	ftype : ttype;
	regs : ttype array;
	code : opcode array;
	debug : (int * int) array;
}

type code = {
	version : int;
	entrypoint : global;
	strings : string array;
	ints : int32 array;
	floats : float array;
	(* types : ttype array // only in bytecode, rebuilt on save() *)
	globals : ttype array;
	natives : (string index * string index * ttype * functable index) array;
	functions : fundecl array;
	debugfiles : string array;
}

(* compiler *)

type ('a,'b) lookup = {
	arr : 'b DynArray.t;
	mutable map : ('a, int) PMap.t;
}

(* not mutable, might be be shared *)
type method_capture = {
	c_map : (int, int) PMap.t;
	c_vars : tvar array;
	c_type : ttype;
}

type method_context = {
	mid : int;
	mregs : (int, ttype) lookup;
	mops : opcode DynArray.t;
	mret : ttype;
	mdebug : (int * int) DynArray.t;
	mutable mcaptured : method_capture;
	mutable mcontinues : (int -> unit) list;
	mutable mbreaks : (int -> unit) list;
	mutable mtrys : int;
	mutable mcaptreg : int;
	mutable mcurpos : (int * int);
}

type array_impl = {
	aall : tclass;
	abase : tclass;
	adyn : tclass;
	aobj : tclass;
	ai32 : tclass;
	af64 : tclass;
}

type context = {
	com : Common.context;
	cglobals : (string, ttype) lookup;
	cstrings : (string, string) lookup;
	cfloats : (float, float) lookup;
	cints : (int32, int32) lookup;
	cnatives : (string, (string index * string index * ttype * functable index)) lookup;
	cfids : (string * path, unit) lookup;
	cfunctions : fundecl DynArray.t;
	overrides : (string * path, bool) Hashtbl.t;
	defined_funs : (int,unit) Hashtbl.t;
	mutable cached_types : (path, ttype) PMap.t;
	mutable m : method_context;
	mutable anons_cache : (tanon * ttype) list;
	mutable method_wrappers : ((ttype * ttype), int) PMap.t;
	mutable rec_cache : Type.t list;
	array_impl : array_impl;
	base_class : tclass;
	base_type : tclass;
	base_enum : tclass;
	core_type : tclass;
	core_enum : tclass;
	cdebug_files : (string, string) lookup;
}

(* --- *)

type access =
	| ANone
	| AGlobal of global
	| ALocal of reg
	| AStaticVar of global * ttype * field index
	| AStaticFun of fundecl index
	| AInstanceFun of texpr * fundecl index
	| AInstanceProto of texpr * field index
	| AInstanceField of texpr * field index
	| AArray of reg * (ttype * ttype) * reg
	| AVirtualMethod of texpr * field index
	| ADynamic of texpr * string index
	| AEnum of field index
	| ACaptured of field index

let is_number = function
	| HI8 | HI16 | HI32 | HF32 | HF64 -> true
	| _ -> false

let hash b =
	let h = ref Int32.zero in
	let rec loop i =
		let c = if i = String.length b then 0 else int_of_char b.[i] in
		if c <> 0 then begin
			h := Int32.add (Int32.mul !h 223l) (Int32.of_int c);
			loop (i + 1)
		end else
			Int32.rem !h 0x1FFFFF7Bl
	in
	loop 0

let list_iteri f l =
	let p = ref 0 in
	List.iter (fun v -> f !p v; incr p) l

let is_extern_field f =
	Type.is_extern_field f || (match f.cf_kind with Method MethNormal -> List.exists (fun (m,_,_) -> m = Meta.Custom ":hlNative") f.cf_meta | _ -> false)

let resolve_field p fid =
	let rec loop pl p =
		let pl = p :: pl in
		match p.psuper with
		| None ->
			let rec fetch id = function
				| [] -> raise Not_found
				| p :: pl ->
					let d = id - Array.length p.pfields in
					if d < 0 then
						let name, _, t = p.pfields.(id) in
						name, t
					else
						fetch d pl
			in
			fetch fid pl
		| Some p ->
			loop pl p
	in
	loop [] p

let rec tstr ?(stack=[]) ?(detailed=false) t =
	match t with
	| HVoid -> "void"
	| HI8 -> "i8"
	| HI16 -> "i16"
	| HI32 -> "i32"
	| HF32 -> "f32"
	| HF64 -> "f64"
	| HBool -> "bool"
	| HBytes -> "bytes"
	| HDyn  -> "dyn"
	| HFun (args,ret) -> "(" ^ String.concat "," (List.map (tstr ~stack ~detailed) args) ^ "):" ^ tstr ~detailed ret
	| HObj o when not detailed -> "#" ^ o.pname
	| HObj o ->
		let fields = "{" ^ String.concat "," (List.map (fun(s,_,t) -> s ^ " : " ^ tstr ~detailed:false t) (Array.to_list o.pfields)) ^ "}" in
		let proto = "{"  ^ String.concat "," (List.map (fun p -> (match p.fvirtual with None -> "" | Some _ -> "virtual ") ^ p.fname ^ "@" ^  string_of_int p.fmethod) (Array.to_list o.pproto)) ^ "}" in
		"#" ^ o.pname ^ "[" ^ (match o.psuper with None -> "" | Some p -> ">" ^ p.pname ^ " ") ^ "fields=" ^ fields ^ " proto=" ^ proto ^ "]"
	| HArray ->
		"array"
	| HType ->
		"type"
	| HRef t ->
		"ref(" ^ tstr t ^ ")"
	| HVirtual v when List.memq v stack ->
		"..."
	| HVirtual v ->
		"virtual(" ^ String.concat "," (List.map (fun (f,_,t) -> f ^":"^tstr ~stack:(v::stack) t) (Array.to_list v.vfields)) ^ ")"
	| HDynObj ->
		"dynobj"
	| HAbstract (s,_) ->
		"abstract(" ^ s ^ ")"
	| HEnum e when e.eid = 0 ->
		let _,_,fl = e.efields.(0) in
		"enum(" ^ String.concat "," (List.map tstr (Array.to_list fl)) ^ ")"
	| HEnum e ->
		"enum(" ^ e.ename ^ ")"
	| HNull t -> "null(" ^ tstr t ^ ")"

let rec tsame t1 t2 =
	if t1 == t2 then true else
	match t1, t2 with
	| HFun (args1,ret1), HFun (args2,ret2) when List.length args1 = List.length args2 -> List.for_all2 tsame args1 args2 && tsame ret2 ret1
	| HObj p1, HObj p2 -> p1 == p2
	| HEnum e1, HEnum e2 -> e1 == e2
	| HAbstract (_,a1), HAbstract (_,a2) -> a1 == a2
	| HVirtual v1, HVirtual v2 ->
		if v1 == v2 then true else
		if Array.length v1.vfields <> Array.length v2.vfields then false else
		let rec loop i =
			if i = Array.length v1.vfields then true else
			let _, i1, t1 = v1.vfields.(i) in
			let _, i2, t2 = v2.vfields.(i) in
			if i1 = i2 && tsame t1 t2 then loop (i + 1) else false
		in
		loop 0
	| HNull t1, HNull t2 -> tsame t1 t2
	| HRef t1, HRef t2 -> tsame t1 t2
	| _ -> false


(*
	does the runtime value can be set to null
*)
let is_nullable t =
	match t with
	| HBytes | HDyn | HFun _ | HObj _ | HArray | HVirtual _ | HDynObj | HAbstract _ | HEnum _ | HNull _ | HRef _ -> true
	| HI8 | HI16 | HI32 | HF32 | HF64 | HBool | HVoid | HType -> false

(*
	does the runtime value carry its type
*)
let is_dynamic t =
	match t with
	| HDyn | HFun _ | HObj _ | HArray | HVirtual _ | HDynObj | HNull _ -> true
	| _ -> false

let is_array_class name =
	match name with
	| "hl.types.ArrayDyn" | "hl.types.ArrayBasic_Int" | "hl.types.ArrayBasic_Float" | "hl.types.ArrayObj" -> true
	| _ -> false

let is_array_type t =
	match t with
	| HObj p -> is_array_class p.pname
	| _ -> false

let rec safe_cast t1 t2 =
	if t1 == t2 then true else
	match t1, t2 with
	| HVirtual _, HDyn -> false
	| _, HDyn -> is_dynamic t1
	| HVirtual v1, HVirtual v2 when Array.length v2.vfields < Array.length v1.vfields ->
		let rec loop i =
			if i = Array.length v2.vfields then true else
			let n1, _, t1 = v1.vfields.(i) in
			let n2, _, t2 = v2.vfields.(i) in
			if n1 = n2 && tsame t1 t2 then loop (i + 1) else false
		in
		loop 0
	| HObj p1, HObj p2 ->
		(* allow subtyping *)
		let rec loop p =
			p.pname = p2.pname || (match p.psuper with None -> false | Some p -> loop p)
		in
		loop p1
	| HFun (args1,t1), HFun (args2,t2) when List.length args1 = List.length args2 ->
		List.for_all2 (fun t1 t2 -> safe_cast t2 t1 || (t1 = HDyn && is_dynamic t2)) args1 args2 && safe_cast t1 t2
	| _ ->
		tsame t1 t2

let utf16_add buf c =
	let add c =
		Buffer.add_char buf (char_of_int (c land 0xFF));
		Buffer.add_char buf (char_of_int (c lsr 8));
	in
	if c >= 0 && c < 0x10000 then begin
		if c >= 0xD800 && c <= 0xDFFF then failwith ("Invalid unicode char " ^ string_of_int c);
		add c;
	end else if c < 0x110000 then begin
		let c = c - 0x10000 in
		add ((c asr 10) + 0xD800);
		add ((c land 1023) + 0xDC00);
	end else
		failwith ("Invalid unicode char " ^ string_of_int c)

let utf8_to_utf16 str =
	let b = Buffer.create (String.length str * 2) in
	(try UTF8.iter (fun c -> utf16_add b (UChar.code c)) str with Invalid_argument _ | UChar.Out_of_range -> ()); (* if malformed *)
	utf16_add b 0;
	Buffer.contents b

let to_utf8 str p =
	let u8 = try
		UTF8.validate str;
		str;
	with
		UTF8.Malformed_code ->
			(* ISO to utf8 *)
			let b = UTF8.Buf.create 0 in
			String.iter (fun c -> UTF8.Buf.add_char b (UChar.of_char c)) str;
			UTF8.Buf.contents b
	in
	let ccount = ref 0 in
	UTF8.iter (fun c ->
		let c = UChar.code c in
		if (c >= 0xD800 && c <= 0xDFFF) || c >= 0x110000 then error "Invalid unicode char" p;
		incr ccount;
		if c > 0x10000 then incr ccount;
	) u8;
	u8, !ccount

let type_size_bits = function
	| HI8 | HBool -> 0
	| HI16 -> 1
	| HI32 | HF32 -> 2
	| HF64 -> 3
	| _ -> assert false

let iteri f l =
	let p = ref (-1) in
	List.iter (fun v -> incr p; f !p v) l

let new_lookup() =
	{
		arr = DynArray.create();
		map = PMap.empty;
	}

let null_proto =
	{
		pname = "";
		pid = 0;
		pclassglobal = None;
		psuper = None;
		pvirtuals = [||];
		pproto = [||];
		pfields = [||];
		pnfields = 0;
		pindex = PMap.empty;
		pfunctions = PMap.empty;
	}

let null_capture =
	{
		c_vars = [||];
		c_map = PMap.empty;
		c_type = HVoid;
	}

let lookup l v fb =
	try
		PMap.find v l.map
	with Not_found ->
		let id = DynArray.length l.arr in
		DynArray.add l.arr (Obj.magic 0);
		l.map <- PMap.add v id l.map;
		DynArray.set l.arr id (fb());
		id

let lookup_alloc l v =
	let id = DynArray.length l.arr in
	DynArray.add l.arr v;
	id

let method_context id t captured =
	{
		mid = id;
		mregs = new_lookup();
		mops = DynArray.create();
		mret = t;
		mbreaks = [];
		mcontinues = [];
		mcaptured = captured;
		mtrys = 0;
		mcaptreg = 0;
		mdebug = DynArray.create();
		mcurpos = (0,0);
	}

let gather_types (code:code) =
	let types = new_lookup() in
	let rec get_type t =
		(match t with HObj { psuper = Some p } -> get_type (HObj p) | _ -> ());
		ignore(lookup types t (fun() ->
			(match t with
			| HFun (args, ret) ->
				List.iter get_type args;
				get_type ret
			| HObj p ->
				Array.iter (fun (_,n,t) -> get_type t) p.pfields
			| HNull t | HRef t ->
				get_type t
			| HVirtual v ->
				Array.iter (fun (_,_,t) -> get_type t) v.vfields
			| HEnum e ->
				Array.iter (fun (_,_,tl) -> Array.iter get_type tl) e.efields
			| _ ->
				());
			t
		));
	in
	List.iter (fun t -> get_type t) [HVoid; HI8; HI16; HI32; HF32; HF64; HBool; HType; HDyn]; (* make sure all basic types get lower indexes *)
	Array.iter (fun g -> get_type g) code.globals;
	Array.iter (fun (_,_,t,_) -> get_type t) code.natives;
	Array.iter (fun f ->
		get_type f.ftype;
		Array.iter (fun r -> get_type r) f.regs;
		Array.iter (function
			| OType (_,t) -> get_type t
			| _ -> ()
		) f.code;
	) code.functions;
	types

let field_name c f =
	s_type_path c.cl_path ^ ":" ^ f.cf_name

let efield_name e f =
	s_type_path e.e_path ^ ":" ^ f.ef_name

let global_type ctx g =
	DynArray.get ctx.cglobals.arr g

let is_overriden ctx c f =
	Hashtbl.mem ctx.overrides (f.cf_name,c.cl_path)

let alloc_float ctx f =
	lookup ctx.cfloats f (fun() -> f)

let alloc_i32 ctx i =
	lookup ctx.cints i (fun() -> i)

let alloc_string ctx s =
	lookup ctx.cstrings s (fun() -> s)

let array_class ctx t =
	match t with
	| HI32 ->
		ctx.array_impl.ai32
	| HF64 ->
		ctx.array_impl.af64
	| HDyn ->
		ctx.array_impl.adyn
	| _ ->
		ctx.array_impl.aobj

let member_fun c t =
	match follow t with
	| TFun (args, ret) -> TFun (("this",false,TInst(c,[])) :: args, ret)
	| _ -> assert false

let rec get_index name p =
	try
		PMap.find name p.pindex
	with Not_found ->
		match p.psuper with
		| None -> raise Not_found
		| Some p -> get_index name p

let rec unsigned t =
	match follow t with
	| TAbstract ({ a_path = ["hl";"types"],("UI32"|"UI16"|"UI8") },_) | TAbstract ({ a_path = [],"UInt" },_) -> true
	| TAbstract (a,pl) -> unsigned (Abstract.get_underlying_type a pl)
	| _ -> false

let set_curpos ctx p =
	let get_relative_path() =
		match Common.defined ctx.com Common.Define.AbsolutePath with
		| true -> if (Filename.is_relative p.pfile)
			then Filename.concat (Sys.getcwd()) p.pfile
			else p.pfile
		| false -> try
			(* lookup relative path *)
			let len = String.length p.pfile in
			let base = List.find (fun path ->
				let l = String.length path in
				len > l && String.sub p.pfile 0 l = path
			) ctx.com.Common.class_path in
			let l = String.length base in
			String.sub p.pfile l (len - l)
		with Not_found ->
			p.pfile
	in
	ctx.m.mcurpos <- (lookup ctx.cdebug_files p.pfile get_relative_path,Lexer.get_error_line p)

let rec to_type ctx t =
	match t with
	| TMono r ->
		(match !r with
		| None -> HDyn
		| Some t -> to_type ctx t)
	| TType (td,tl) ->
		if List.memq t ctx.rec_cache then
			error "Unsupported recursive type" td.t_pos
		else begin
			ctx.rec_cache <- t :: ctx.rec_cache;
			let t = (match td.t_path with
			| [], "Null" ->
				let t = to_type ctx (apply_params td.t_params tl td.t_type) in
				if is_nullable t then t else HNull t
			| _ ->
				to_type ctx (apply_params td.t_params tl td.t_type)
			) in
			ctx.rec_cache <- List.tl ctx.rec_cache;
			t
		end
	| TLazy f ->
		to_type ctx (!f())
	| TFun (args, ret) ->
		HFun (List.map (fun (_,o,t) -> to_type ctx (if o then ctx.com.basic.tnull t else t)) args, to_type ctx ret)
	| TAnon a when (match !(a.a_status) with Statics _ | EnumStatics _ -> true | _ -> false) ->
		(match !(a.a_status) with
		| Statics c ->
			class_type ctx c (List.map snd c.cl_params) true
		| EnumStatics e ->
			enum_class ctx e
		| _ -> assert false)
	| TAnon a ->
		(try
			(* can't use physical comparison in PMap since addresses might change in GC compact,
				maybe add an uid to tanon if too slow ? *)
			List.assq a ctx.anons_cache
		with Not_found ->
			let vp = {
				vfields = [||];
				vindex = PMap.empty;
			} in
			let t = HVirtual vp in
			ctx.anons_cache <- (a,t) :: ctx.anons_cache;
			let fields = PMap.fold (fun cf acc ->
				match cf.cf_kind with
				| Var { v_read = AccNo } | Var { v_write = AccNo } ->
					(*
						if there's read-only/write-only fields, it will allow variance, so let's
						handle the field access as fully Dynamic
					*)
					acc
				| Var _ when has_meta Meta.Optional cf.cf_meta ->
					(*
						if it's optional it might not be present, handle the field access as fully Dynamic
					*)
					acc
				| Var _ when (match follow cf.cf_type with TAnon _ | TFun _ -> true | _ -> false) ->
					(*
						if it's another virtual or a method, it might not match our own (might be larger, or class)
					*)
					acc
				| Method _ ->
					acc
				| _ ->
					(cf.cf_name,alloc_string ctx cf.cf_name,to_type ctx cf.cf_type) :: acc
			) a.a_fields [] in
			if fields = [] then
				let t = HDyn in
				ctx.anons_cache <- (a,t) :: List.tl ctx.anons_cache;
				t
			else
				let fields = List.sort (fun (n1,_,_) (n2,_,_) -> compare n1 n2) fields in
				vp.vfields <- Array.of_list fields;
				Array.iteri (fun i (n,_,_) -> vp.vindex <- PMap.add n i vp.vindex) vp.vfields;
				t
		)
	| TDynamic _ ->
		HDyn
	| TEnum (e,_) ->
		enum_type ctx e
	| TInst ({ cl_path = ["hl";"types"],"NativeAbstract" },[TInst({ cl_kind = KExpr (EConst (String name),_) },_)]) ->
		HAbstract (name, alloc_string ctx name)
	| TInst (c,pl) ->
		(match c.cl_kind with
		| KTypeParameter tl ->
			let rec loop = function
				| [] -> HDyn
				| t :: tl ->
					match follow (apply_params c.cl_params pl t) with
					| TInst ({cl_interface=false},_) as t -> to_type ctx t
					| _ -> loop tl
			in
			loop tl
		| _ -> class_type ctx c pl false)
	| TAbstract (a,pl) ->
		if Meta.has Meta.CoreType a.a_meta then
			(match a.a_path with
			| [], "Void" -> HVoid
			| [], "Int" | [], "UInt" -> HI32
			| [], "Float" -> HF64
			| [], "Single" -> HF32
			| [], "Bool" -> HBool
			| [], "Dynamic" -> HDyn
			| [], "Class" ->
				let c, pl, s = (match follow (List.hd pl) with
					| TDynamic _ | TInst ({cl_kind = KTypeParameter _ },_) | TMono _ | TAnon _ -> ctx.base_class, [], false
					| TInst (c,pl) -> c, pl, true
					| t -> assert false
				) in
				class_type ctx c pl s
			| [], "Enum" ->
				class_type ctx ctx.base_type [] false
			| [], "EnumValue" -> HDyn
			| ["hl";"types"], "Ref" -> HRef (to_type ctx (List.hd pl))
			| ["hl";"types"], ("Bytes" | "BytesAccess") -> HBytes
			| ["hl";"types"], "Type" -> HType
			| ["hl";"types"], "NativeArray" -> HArray
			| _ -> failwith ("Unknown core type " ^ s_type_path a.a_path))
		else
			to_type ctx (Abstract.get_underlying_type a pl)

and resolve_class ctx c pl statics =
	let not_supported() =
		failwith ("Extern type not supported : " ^ s_type (print_context()) (TInst (c,pl)))
	in
	match c.cl_path, pl with
	| ([],"Array"), [t] ->
		if statics then ctx.array_impl.abase else array_class ctx (to_type ctx t)
	| ([],"Array"), [] ->
		assert false
	| _, _ when c.cl_extern ->
		not_supported()
	| _ ->
		c

and field_type ctx f p =
	match f with
	| FInstance (c,pl,f) | FClosure (Some (c,pl),f) ->
		let creal = resolve_class ctx c pl false in
		let rec loop c =
			try
				PMap.find f.cf_name c.cl_fields
			with Not_found ->
				match c.cl_super with
				| Some (csup,_) -> loop csup
				| None -> error (s_type_path creal.cl_path ^ " is missing field " ^ f.cf_name) p
		in
		(loop creal).cf_type
	| FStatic (_,f) | FAnon f | FClosure (_,f) -> f.cf_type
	| FDynamic _ -> t_dynamic
	| FEnum (_,f) -> f.ef_type

and real_type ctx e =
	let rec loop e =
		match e.eexpr with
		| TField (_,f) -> field_type ctx f e.epos
		| TLocal v -> v.v_type
		| TParenthesis e -> loop e
		| _ -> e.etype
	in
	to_type ctx (loop e)

and class_type ctx c pl statics =
	let c = if c.cl_extern then resolve_class ctx c pl statics else c in
	let key_path = (if statics then fst c.cl_path, "$" ^ snd c.cl_path else c.cl_path) in
	try
		PMap.find key_path ctx.cached_types
	with Not_found when c.cl_interface && not statics ->
		let vp = {
			vfields = [||];
			vindex = PMap.empty;
		} in
		let t = HVirtual vp in
		ctx.cached_types <- PMap.add c.cl_path t ctx.cached_types;
		let fields = PMap.fold (fun cf acc -> (cf.cf_name,alloc_string ctx cf.cf_name,to_type ctx cf.cf_type) :: acc) c.cl_fields [] in
		vp.vfields <- Array.of_list fields;
		Array.iteri (fun i (n,_,_) -> vp.vindex <- PMap.add n i vp.vindex) vp.vfields;
		t
	| Not_found ->
		let pname = s_type_path key_path in
		let p = {
			pname = pname;
			pid = alloc_string ctx pname;
			psuper = None;
			pclassglobal = None;
			pproto = [||];
			pfields = [||];
			pindex = PMap.empty;
			pvirtuals = [||];
			pfunctions = PMap.empty;
			pnfields = -1;
		} in
		let t = HObj p in
		ctx.cached_types <- PMap.add key_path t ctx.cached_types;
		if c.cl_path = ([],"Array") then assert false;
		if c == ctx.base_class then begin
			if statics then assert false;
			p.pnfields <- 1;
		end;
		let tsup = (match c.cl_super with
			| None -> if statics then Some (class_type ctx ctx.base_class [] false) else None
			| Some (csup,pl) -> Some (class_type ctx csup [] statics)
		) in
		let start_field, virtuals = (match tsup with
			| None -> 0, [||]
			| Some (HObj psup) ->
				if psup.pnfields < 0 then assert false;
				p.psuper <- Some psup;
				p.pfunctions <- psup.pfunctions;
				psup.pnfields, psup.pvirtuals
			| _ -> assert false
		) in
		let fa = DynArray.create() and pa = DynArray.create() and virtuals = DynArray.of_array virtuals in
		let todo = ref [] in
		List.iter (fun f ->
			if is_extern_field f || (statics && f.cf_name = "__meta__") then () else
			match f.cf_kind with
			| Method m when m <> MethDynamic && not statics ->
				let g = alloc_fid ctx c f in
				p.pfunctions <- PMap.add f.cf_name g p.pfunctions;
				let virt = if List.exists (fun ff -> ff.cf_name = f.cf_name) c.cl_overrides then
					let vid = (try -(fst (get_index f.cf_name p))-1 with Not_found -> assert false) in
					DynArray.set virtuals vid g;
					Some vid
				else if is_overriden ctx c f then begin
					let vid = DynArray.length virtuals in
					DynArray.add virtuals g;
					p.pindex <- PMap.add f.cf_name (-vid-1,HVoid) p.pindex;
					Some vid
				end else
					None
				in
				DynArray.add pa { fname = f.cf_name; fid = alloc_string ctx f.cf_name; fmethod = g; fvirtual = virt; }
			| _ ->
				let fid = DynArray.length fa in
				p.pindex <- PMap.add f.cf_name (fid + start_field, t) p.pindex;
				DynArray.add fa (f.cf_name, alloc_string ctx f.cf_name, HVoid);
				todo := (fun() ->
					let t = to_type ctx f.cf_type in
					p.pindex <- PMap.add f.cf_name (fid + start_field, t) p.pindex;
					Array.set p.pfields fid (f.cf_name, alloc_string ctx f.cf_name, t)
				) :: !todo;
		) (if statics then c.cl_ordered_statics else c.cl_ordered_fields);
		if not statics then (try
			let cf = PMap.find "toString" c.cl_fields in
			if List.memq cf c.cl_overrides || PMap.mem "__string" c.cl_fields then raise Not_found;
			DynArray.add pa { fname = "__string"; fid = alloc_string ctx "__string"; fmethod = alloc_fun_path ctx c.cl_path "__string"; fvirtual = None; }
		with Not_found ->
			());
		p.pnfields <- DynArray.length fa + start_field;
		p.pfields <- DynArray.to_array fa;
		p.pproto <- DynArray.to_array pa;
		p.pvirtuals <- DynArray.to_array virtuals;
		List.iter (fun f -> f()) !todo;
		if not statics && c != ctx.core_type && c != ctx.core_enum then p.pclassglobal <- Some (fst (class_global ctx (if statics then ctx.base_class else c)));
		t

and enum_type ctx e =
	try
		PMap.find e.e_path ctx.cached_types
	with Not_found ->
		let ename = s_type_path e.e_path in
		let et = {
			eglobal = 0;
			ename = ename;
			eid = alloc_string ctx ename;
			efields = [||];
		} in
		let t = HEnum et in
		ctx.cached_types <- PMap.add e.e_path t ctx.cached_types;
		et.efields <- Array.of_list (List.map (fun f ->
			let f = PMap.find f e.e_constrs in
			let args = (match f.ef_type with
				| TFun (args,_) -> Array.of_list (List.map (fun (_,_,t) -> to_type ctx t) args)
				| _ -> [||]
			) in
			(f.ef_name, alloc_string ctx f.ef_name, args)
		) e.e_names);
		let ct = enum_class ctx e in
		et.eglobal <- alloc_global ctx (match ct with HObj o -> o.pname | _ -> assert false) ct;
		t

and enum_class ctx e =
	let cpath = (fst e.e_path,"$" ^ snd e.e_path) in
	try
		PMap.find cpath ctx.cached_types
	with Not_found ->
		let pname = s_type_path cpath in
		let p = {
			pname = pname;
			pid = alloc_string ctx pname;
			psuper = None;
			pclassglobal = None;
			pproto = [||];
			pfields = [||];
			pindex = PMap.empty;
			pvirtuals = [||];
			pfunctions = PMap.empty;
			pnfields = -1;
		} in
		let t = HObj p in
		ctx.cached_types <- PMap.add cpath t ctx.cached_types;
		p.psuper <- Some (match class_type ctx ctx.base_enum [] false with HObj o -> o | _ -> assert false);
		t

and alloc_fun_path ctx path name =
	lookup ctx.cfids (name, path) (fun() -> ())

and alloc_fid ctx c f =
	match f.cf_kind with
	| Var _ -> assert false
	| _ -> alloc_fun_path ctx c.cl_path f.cf_name

and alloc_eid ctx e f =
	alloc_fun_path ctx e.e_path f.ef_name

and alloc_function_name ctx f =
	alloc_fun_path ctx ([],"") f

and alloc_global ctx name t =
	lookup ctx.cglobals name (fun() -> t)

and class_global ?(resolve=true) ctx c =
	let static = c != ctx.base_class in
	let c = if resolve && is_array_type (HObj { null_proto with pname = s_type_path c.cl_path }) then ctx.array_impl.abase else c in
	let c = resolve_class ctx c (List.map snd c.cl_params) static in
	let t = class_type ctx c [] static in
	alloc_global ctx ("$" ^ s_type_path c.cl_path) t, t

let alloc_std ctx name args ret =
	let lib = "std" in
	(* different from :hlNative to prevent mismatch *)
	let nid = lookup ctx.cnatives ("$" ^ name ^ "@" ^ lib) (fun() ->
		let fid = alloc_fun_path ctx ([],"std") name in
		Hashtbl.add ctx.defined_funs fid ();
		(alloc_string ctx lib, alloc_string ctx name,HFun (args,ret),fid)
	) in
	let _,_,_,fid = DynArray.get ctx.cnatives.arr nid in
	fid

let is_int ctx t =
	match to_type ctx t with
	| HI8 | HI16 | HI32 -> true
	| _ -> false

let is_float ctx t =
	match to_type ctx t with
	| HF32 | HF64 -> true
	| _ -> false

let alloc_reg ctx v =
	lookup ctx.m.mregs v.v_id (fun() -> to_type ctx v.v_type)

let alloc_tmp ctx t =
	let rid = DynArray.length ctx.m.mregs.arr in
	DynArray.add ctx.m.mregs.arr t;
	rid

let current_pos ctx =
	DynArray.length ctx.m.mops

let op ctx o =
	DynArray.add ctx.m.mdebug ctx.m.mcurpos;
	DynArray.add ctx.m.mops o

let jump ctx f =
	let pos = current_pos ctx in
	op ctx (OJAlways (-1)); (* loop *)
	(fun() -> DynArray.set ctx.m.mops pos (f (current_pos ctx - pos - 1)))

let jump_back ctx =
	let pos = current_pos ctx in
	op ctx (OLabel 0);
	(fun() -> op ctx (OJAlways (pos - current_pos ctx - 1)))

let rtype ctx r =
	DynArray.get ctx.m.mregs.arr r

let reg_int ctx v =
	let r = alloc_tmp ctx HI32 in
	op ctx (OInt (r,alloc_i32 ctx (Int32.of_int v)));
	r

let shl ctx idx v =
	if v = 0 then idx else
	let idx2 = alloc_tmp ctx HI32 in
	op ctx (OShl (idx2, idx, reg_int ctx v));
	idx2

let set_default ctx r =
	match rtype ctx r with
	| HI8 | HI16 | HI32 ->
		op ctx (OInt (r,alloc_i32 ctx 0l))
	| HF32 | HF64 ->
		op ctx (OFloat (r,alloc_float ctx 0.))
	| HBool ->
		op ctx (OBool (r, false))
	| HType ->
		op ctx (OType (r, HVoid))
	| _ ->
		op ctx (ONull r)

let read_mem ctx rdst bytes index t =
	match t with
	| HI8 ->
		op ctx (OGetI8 (rdst,bytes,index))
(*	| HI16 ->
		op ctx (OGetI16 (rdst,bytes,index))*)
	| HI32 ->
		op ctx (OGetI32 (rdst,bytes,index))
	| HF32 ->
		op ctx (OGetF32 (rdst,bytes,index))
	| HF64 ->
		op ctx (OGetF64 (rdst,bytes,index))
	| _ ->
		assert false

let write_mem ctx bytes index t r=
	match t with
	| HI8 ->
		op ctx (OSetI8 (bytes,index,r))
(*	| HI16 ->
		op ctx (OSetI16 (bytes,index,r))*)
	| HI32 ->
		op ctx (OSetI32 (bytes,index,r))
	| HF32 ->
		op ctx (OSetF32 (bytes,index,r))
	| HF64 ->
		op ctx (OSetF64 (bytes,index,r))
	| _ ->
		assert false

let common_type ctx e1 e2 for_eq p =
	let t1 = to_type ctx e1.etype in
	let t2 = to_type ctx e2.etype in
	let rec loop t1 t2 =
		if t1 == t2 then t1 else
		match t1, t2 with
		| HI8, (HI16 | HI32 | HF32 | HF64) -> t2
		| HI16, (HI32 | HF32 | HF64) -> t2
		| HI32, HF32 -> t2 (* possible loss of precision *)
		| (HI32 | HF32), HF64 -> t2
		| (HI8|HI16|HI32|HF32|HF64), (HI8|HI16|HI32|HF32|HF64) -> t1
		| (HI8|HI16|HI32|HF32|HF64), (HNull t2) -> if for_eq then HNull (loop t1 t2) else loop t1 t2
		| (HNull t1), (HI8|HI16|HI32|HF32|HF64) -> if for_eq then HNull (loop t1 t2) else loop t1 t2
		| HDyn, (HI8|HI16|HI32|HF32|HF64) -> HF64
		| (HI8|HI16|HI32|HF32|HF64), HDyn -> HF64
		| HDyn, _ -> HDyn
		| _, HDyn -> HDyn
		| _ when for_eq && safe_cast t1 t2 -> t2
		| _ when for_eq && safe_cast t2 t1 -> t1
		| HBool, HNull HBool when for_eq -> t2
		| HNull HBool, HBool when for_eq -> t1
		| _ ->
			error ("Don't know how to compare " ^ tstr t1 ^ " and " ^ tstr t2) p
	in
	loop t1 t2

let captured_index ctx v =
	if not v.v_capture then None else try Some (PMap.find v.v_id ctx.m.mcaptured.c_map) with Not_found -> None

let before_return ctx =
	let rec loop i =
		if i > 0 then begin
			op ctx (OEndTrap 0);
			loop (i - 1)
		end
	in
	loop ctx.m.mtrys

let rec eval_to ctx e (t:ttype) =
	let r = eval_expr ctx e in
	cast_to ctx r t e.epos

and cast_to ?(force=false) ctx (r:reg) (t:ttype) p =
	let rt = rtype ctx r in
	if safe_cast rt t then r else
	match rt, t with
	| _, HVoid ->
		alloc_tmp ctx HVoid
	| HVirtual _, HDyn ->
		let tmp = alloc_tmp ctx HDyn in
		op ctx (OUnVirtual (tmp,r));
		tmp
	| HVirtual _, HVirtual _ ->
		let tmp = alloc_tmp ctx HDyn in
		op ctx (OUnVirtual (tmp,r));
		cast_to ctx tmp t p
	| (HI8 | HI16 | HI32 | HF32 | HF64), (HF32 | HF64) ->
		let tmp = alloc_tmp ctx t in
		op ctx (OToSFloat (tmp, r));
		tmp
	| (HF32 | HF64), (HI8 | HI16 | HI32) ->
		let tmp = alloc_tmp ctx t in
		op ctx (OToInt (tmp, r));
		tmp
	| (HI8 | HI16 | HI32), HNull ((HF32 | HF64) as t) ->
		let tmp = alloc_tmp ctx t in
		op ctx (OToSFloat (tmp, r));
		let r = alloc_tmp ctx (HNull t) in
		op ctx (OToDyn (r,tmp));
		r
	| (HI8 | HI16 | HI32), HObj { pname = "String" } ->
		let out = alloc_tmp ctx t in
		let len = alloc_tmp ctx HI32 in
		let lref = alloc_tmp ctx (HRef HI32) in
		let bytes = alloc_tmp ctx HBytes in
		op ctx (ORef (lref,len));
		op ctx (OCall2 (bytes,alloc_std ctx "itos" [HI32;HRef HI32] HBytes,cast_to ctx r HI32 p,lref));
		op ctx (OCall2 (out,alloc_fun_path ctx ([],"String") "__alloc__",bytes,len));
		out
	| (HF32 | HF64), HObj { pname = "String" } ->
		let out = alloc_tmp ctx t in
		let len = alloc_tmp ctx HI32 in
		let lref = alloc_tmp ctx (HRef HI32) in
		let bytes = alloc_tmp ctx HBytes in
		op ctx (ORef (lref,len));
		op ctx (OCall2 (bytes,alloc_std ctx "ftos" [HF64;HRef HI32] HBytes,cast_to ctx r HF64 p,lref));
		op ctx (OCall2 (out,alloc_fun_path ctx ([],"String") "__alloc__",bytes,len));
		out
	| _, HObj { pname = "String" } ->
		let out = alloc_tmp ctx t in
		let r = cast_to ctx r HDyn p in
		op ctx (OJNotNull (r,2));
		op ctx (ONull out);
		op ctx (OJAlways 1);
		op ctx (OCall1 (out,alloc_fun_path ctx ([],"Std") "string",r));
		out
	| (HObj _ | HDynObj | HDyn) , HVirtual _ ->
		let out = alloc_tmp ctx t in
		op ctx (OToVirtual (out,r));
		out
	| HDyn, _ ->
		let out = alloc_tmp ctx t in
		op ctx (OSafeCast (out, r));
		out
	| HNull rt, _ when t = rt ->
		let out = alloc_tmp ctx t in
		op ctx (OSafeCast (out, r));
		out
	| _ , HDyn ->
		let tmp = alloc_tmp ctx HDyn in
		op ctx (OToDyn (tmp, r));
		tmp
	| _, HNull t when rt == t ->
		let tmp = alloc_tmp ctx (HNull t) in
		op ctx (OToDyn (tmp, r));
		tmp
	| HNull t1, HNull t2 ->
		let j = jump ctx (fun n -> OJNull (r,n)) in
		let rtmp = alloc_tmp ctx t1 in
		op ctx (OSafeCast (rtmp,r));
		let out = cast_to ctx rtmp t p in
		op ctx (OJAlways 1);
		j();
		op ctx (ONull out);
		out
	| HFun (args1,ret1), HFun (args2, ret2) when List.length args1 = List.length args2 ->
		let fid = gen_method_wrapper ctx rt t p in
		let fr = alloc_tmp ctx t in
		op ctx (OJNotNull (r,2));
		op ctx (ONull fr);
		op ctx (OJAlways 1);
		op ctx (OClosure (fr,fid,r));
		fr
	| HObj _, HObj _ when is_array_type rt && is_array_type t ->
		let out = alloc_tmp ctx t in
		op ctx (OSafeCast (out, r));
		out
	| _ ->
		if force then
			let out = alloc_tmp ctx t in
			op ctx (OSafeCast (out, r));
			out
		else
			error ("Don't know how to cast " ^ tstr rt ^ " to " ^ tstr t) p

and unsafe_cast_to ctx (r:reg) (t:ttype) p =
	let rt = rtype ctx r in
	if safe_cast rt t then
		r
	else
	match rt with
	| HFun _ ->
		cast_to ctx r t p
	| HDyn when is_array_type t ->
		cast_to ctx r t p
	| HDyn when (match t with HVirtual _ -> true | _ -> false) ->
		cast_to ctx r t p
	| HObj _ when is_array_type rt && is_array_type t ->
		cast_to ctx r t p
	| _ ->
		if is_dynamic (rtype ctx r) && is_dynamic t then
			let r2 = alloc_tmp ctx t in
			op ctx (OUnsafeCast (r2,r));
			r2
		else
			cast_to ~force:true ctx r t p

and object_access ctx eobj t f =
	match t with
	| HObj p ->
		(try
			let fid = fst (get_index f.cf_name p) in
			if f.cf_kind = Method MethNormal then
				AInstanceProto (eobj, -fid-1)
			else
				AInstanceField (eobj, fid)
		with Not_found ->
			ADynamic (eobj, alloc_string ctx f.cf_name))
	| HVirtual v ->
		(try
			let fid = PMap.find f.cf_name v.vindex in
			if f.cf_kind = Method MethNormal then
				AVirtualMethod (eobj, fid)
			else
				AInstanceField (eobj, fid)
		with Not_found ->
			ADynamic (eobj, alloc_string ctx f.cf_name))
	| HDyn ->
		ADynamic (eobj, alloc_string ctx f.cf_name)
	| _ ->
		error ("Unsupported field access " ^ tstr t) eobj.epos

and get_access ctx e =
	match e.eexpr with
	| TField (ethis, a) ->
		(match a, follow ethis.etype with
		| FStatic (c,({ cf_kind = Var _ | Method MethDynamic } as f)), _ ->
			let g, t = class_global ctx c in
			AStaticVar (g, t, (match t with HObj o -> (try fst (get_index f.cf_name o) with Not_found -> assert false) | _ -> assert false))
		| FStatic (c,({ cf_kind = Method _ } as f)), _ ->
			AStaticFun (alloc_fid ctx c f)
		| FClosure (Some (cdef,pl), ({ cf_kind = Method m } as f)), TInst (c,_)
		| FInstance (cdef,pl,({ cf_kind = Method m } as f)), TInst (c,_) when m <> MethDynamic && not (c.cl_interface || (is_overriden ctx c f && ethis.eexpr <> TConst(TSuper))) ->
			AInstanceFun (ethis, alloc_fid ctx (resolve_class ctx cdef pl false) f)
		| FInstance (cdef,pl,f), _ | FClosure (Some (cdef,pl), f), _ ->
			object_access ctx ethis (class_type ctx cdef pl false) f
		| (FAnon f | FClosure(None,f)), _ ->
			object_access ctx ethis (to_type ctx ethis.etype) f
		| FDynamic name, _ ->
			ADynamic (ethis, alloc_string ctx name)
		| FEnum (e,ef), _ ->
			(match follow ef.ef_type with
			| TFun _ -> AEnum ef.ef_index
			| t -> AGlobal (alloc_global ctx (efield_name e ef) (to_type ctx t))))
	| TLocal v ->
		(match captured_index ctx v with
		| None -> ALocal (alloc_reg ctx v)
		| Some idx -> ACaptured idx)
	| TParenthesis e ->
		get_access ctx e
	| TArray (a,i) ->
		(match follow a.etype with
		| TInst({ cl_path = [],"Array" },[t]) ->
			let a = eval_null_check ctx a in
			let i = eval_to ctx i HI32 in
			let t = to_type ctx t in
			AArray (a,(t,t),i)
		| _ ->
			let a = eval_to ctx a (class_type ctx ctx.array_impl.adyn [] false) in
			op ctx (ONullCheck a);
			let i = eval_to ctx i HI32 in
			AArray (a,(HDyn,to_type ctx e.etype),i)
		)
	| _ ->
		ANone

and array_read ctx ra (at,vt) ridx p =
	match at with
	| HI8 | HI16 | HI32 | HF32 | HF64 ->
		(* check bounds *)
		let length = alloc_tmp ctx HI32 in
		op ctx (OField (length, ra, 0));
		let r = alloc_tmp ctx at in
		let j = jump ctx (fun i -> OJULt (ridx,length,i)) in
		(match at with
		| HI8 | HI16 | HI32 ->
			op ctx (OInt (r,alloc_i32 ctx 0l));
		| HF32 | HF64 ->
			op ctx (OFloat (r,alloc_float ctx 0.));
		| _ ->
			assert false);
		let jend = jump ctx (fun i -> OJAlways i) in
		j();
		let hbytes = alloc_tmp ctx HBytes in
		op ctx (OField (hbytes, ra, 1));
		read_mem ctx r hbytes (shl ctx ridx (type_size_bits at)) at;
		jend();
		cast_to ctx r vt p
	| HDyn ->
		(* call getDyn *)
		let r = alloc_tmp ctx HDyn in
		op ctx (OCallMethod (r,0,[ra;ridx]));
		unsafe_cast_to ctx r vt p
	| _ ->
		(* check bounds *)
		let length = alloc_tmp ctx HI32 in
		op ctx (OField (length,ra,0));
		let r = alloc_tmp ctx vt in
		let j = jump ctx (fun i -> OJULt (ridx,length,i)) in
		set_default ctx r;
		let jend = jump ctx (fun i -> OJAlways i) in
		j();
		let tmp = alloc_tmp ctx HDyn in
		let harr = alloc_tmp ctx HArray in
		op ctx (OField (harr,ra,1));
		op ctx (OGetArray (tmp,harr,ridx));
		op ctx (OMov (r,unsafe_cast_to ctx tmp vt p));
		jend();
		r

and jump_expr ctx e jcond =
	match e.eexpr with
	| TParenthesis e ->
		jump_expr ctx e jcond
	| TUnop (Not,_,e) ->
		jump_expr ctx e (not jcond)
	| TBinop (OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte as jop, e1, e2) ->
		let t = common_type ctx e1 e2 (match jop with OpEq | OpNotEq -> true | _ -> false) e.epos in
		let r1 = eval_to ctx e1 t in
		let r2 = eval_to ctx e2 t in
		let unsigned = unsigned e1.etype && unsigned e2.etype in
		jump ctx (fun i ->
			let lt a b = if unsigned then OJULt (a,b,i) else OJSLt (a,b,i) in
			let gte a b = if unsigned then OJUGte (a,b,i) else OJSGte (a,b,i) in
			match jop with
			| OpEq -> if jcond then OJEq (r1,r2,i) else OJNotEq (r1,r2,i)
			| OpNotEq -> if jcond then OJNotEq (r1,r2,i) else OJEq (r1,r2,i)
			| OpGt -> if jcond then lt r2 r1 else gte r2 r1
			| OpGte -> if jcond then gte r1 r2 else lt r1 r2
			| OpLt -> if jcond then lt r1 r2 else gte r1 r2
			| OpLte -> if jcond then gte r2 r1 else lt r2 r1
			| _ -> assert false
		)
	| TBinop (OpBoolAnd, e1, e2) ->
		let j = jump_expr ctx e1 false in
		let j2 = jump_expr ctx e2 jcond in
		if jcond then j();
		(fun() -> if not jcond then j(); j2());
	| TBinop (OpBoolOr, e1, e2) ->
		let j = jump_expr ctx e1 true in
		let j2 = jump_expr ctx e2 jcond in
		if not jcond then j();
		(fun() -> if jcond then j(); j2());
	| _ ->
		let r = eval_to ctx e HBool in
		jump ctx (fun i -> if jcond then OJTrue (r,i) else OJFalse (r,i))

and eval_args ctx el t p =
	let rl = List.map2 (fun e t -> eval_to ctx e t) el (match t with HFun (args,_) -> args | HDyn -> List.map (fun _ -> HDyn) el | _ -> assert false) in
	set_curpos ctx p;
	rl

and eval_null_check ctx e =
	let r = eval_expr ctx e in
	(match e.eexpr with
	| TConst TThis | TConst TSuper -> ()
	| _ -> op ctx (ONullCheck r));
	r

and make_string ctx s p =
	let str, len = to_utf8 s p in
	let r = alloc_tmp ctx HBytes in
	let s = alloc_tmp ctx (to_type ctx ctx.com.basic.tstring) in
	op ctx (ONew s);
	op ctx (OString (r,alloc_string ctx str));
	op ctx (OSetField (s,0,r));
	op ctx (OSetField (s,1,reg_int ctx len));
	s

and eval_expr ctx e =
	set_curpos ctx e.epos;
	match e.eexpr with
	| TConst c ->
		(match c with
		| TInt i ->
			let r = alloc_tmp ctx HI32 in
			op ctx (OInt (r,alloc_i32 ctx i));
			r
		| TFloat f ->
			let r = alloc_tmp ctx HF64 in
			op ctx (OFloat (r,alloc_float ctx (float_of_string f)));
			r
		| TBool b ->
			let r = alloc_tmp ctx HBool in
			op ctx (OBool (r,b));
			r
		| TString s ->
			make_string ctx s e.epos
		| TThis | TSuper ->
			0 (* first reg *)
		| _ ->
			let r = alloc_tmp ctx (to_type ctx e.etype) in
			op ctx (ONull r);
			r)
	| TVar (v,e) ->
		(match e with
		| None -> ()
		| Some e ->
			match captured_index ctx v with
			| None ->
				let r = alloc_reg ctx v in
				let ri = eval_to ctx e (rtype ctx r) in
				op ctx (OMov (r,ri))
			| Some idx ->
				let ri = eval_to ctx e (to_type ctx v.v_type) in
				op ctx (OSetEnumField (ctx.m.mcaptreg, idx, ri));
		);
		alloc_tmp ctx HVoid
	| TLocal v ->
		cast_to ctx (match captured_index ctx v with
		| None ->
			(* we need to make a copy for cases such as (a - a++) *)
			let r = alloc_reg ctx v in
			let r2 = alloc_tmp ctx (rtype ctx r) in
			op ctx (OMov (r2, r));
			r2
		| Some idx ->
			let r = alloc_tmp ctx (to_type ctx v.v_type) in
			op ctx (OEnumField (r, ctx.m.mcaptreg, 0, idx));
			r) (to_type ctx e.etype) e.epos
	| TReturn None ->
		before_return ctx;
		let r = alloc_tmp ctx HVoid in
		op ctx (ORet r);
		r
	| TReturn (Some e) ->
		let r = eval_to ctx e ctx.m.mret in
		before_return ctx;
		op ctx (ORet r);
		alloc_tmp ctx HVoid
	| TParenthesis e ->
		eval_expr ctx e
	| TBlock el ->
		let rec loop = function
			| [e] -> eval_expr ctx e
			| [] -> alloc_tmp ctx HVoid
			| e :: l ->
				ignore(eval_expr ctx e);
				loop l
		in
		loop el
	| TCall ({ eexpr = TConst TSuper } as s, el) ->
		(match follow s.etype with
		| TInst (csup,_) ->
			(match csup.cl_constructor with
			| None -> assert false
			| Some f ->
				let r = alloc_tmp ctx HVoid in
				let el = eval_args ctx el (to_type ctx f.cf_type) e.epos in
				op ctx (OCallN (r, alloc_fid ctx csup f, 0 :: el));
				r
			)
		| _ -> assert false);
	| TCall ({ eexpr = TLocal v }, el) when v.v_name.[0] = '$' ->
		let invalid() = error "Invalid native call" e.epos in
		(match v.v_name, el with
		| "$new", [{ eexpr = TTypeExpr (TClassDecl _) }] ->
			(match follow e.etype with
			| TInst (c,pl) ->
				let r = alloc_tmp ctx (class_type ctx c pl false) in
				op ctx (ONew r);
				r
			| _ ->
				invalid())
		| "$int", [{ eexpr = TBinop (OpDiv, e1, e2) }] when is_int ctx e1.etype && is_int ctx e2.etype ->
			let tmp = alloc_tmp ctx HI32 in
			op ctx (if unsigned e1.etype && unsigned e2.etype then OUDiv (tmp, eval_to ctx e1 HI32, eval_to ctx e2 HI32) else OSDiv (tmp, eval_to ctx e1 HI32, eval_to ctx e2 HI32));
			tmp
		| "$int", [e] ->
			let tmp = alloc_tmp ctx HI32 in
			op ctx (OToInt (tmp, eval_expr ctx e));
			tmp
		| "$balloc", [e] ->
			let f = alloc_std ctx "balloc" [HI32] HBytes in
			let tmp = alloc_tmp ctx HBytes in
			op ctx (OCall1 (tmp, f, eval_to ctx e HI32));
			tmp
		| "$bblit", [b;dp;src;sp;len] ->
			let f = alloc_std ctx "bblit" [HBytes;HI32;HBytes;HI32;HI32] HVoid in
			let tmp = alloc_tmp ctx HVoid in
			op ctx (OCallN (tmp, f, [eval_to ctx b HBytes;eval_to ctx dp HI32;eval_to ctx src HBytes;eval_to ctx sp HI32; eval_to ctx len HI32]));
			tmp
		| "$bseti8", [b;pos;v] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = eval_to ctx v HI32 in
			op ctx (OSetI8 (b, pos, r));
			r
		| "$bseti32", [b;pos;v] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = eval_to ctx v HI32 in
			op ctx (OSetI32 (b, pos, r));
			r
		| "$bsetf32", [b;pos;v] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = eval_to ctx v HF32 in
			op ctx (OSetF32 (b, pos, r));
			r
		| "$bsetf64", [b;pos;v] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = eval_to ctx v HF64 in
			op ctx (OSetF64 (b, pos, r));
			r
		| "$bytes_sizebits", [eb] ->
			(match follow eb.etype with
			| TAbstract({a_path = ["hl";"types"],"BytesAccess"},[t]) ->
				reg_int ctx (match to_type ctx t with
				| HI8 -> 0
				| HI16 -> 1
				| HI32 -> 2
				| HF32 -> 2
				| HF64 -> 3
				| t -> error ("Unsupported basic type " ^ tstr t) e.epos)
			| _ ->
				error "Invalid BytesAccess" eb.epos);
		| "$bytes_nullvalue", [eb] ->
			(match follow eb.etype with
			| TAbstract({a_path = ["hl";"types"],"BytesAccess"},[t]) ->
				let t = to_type ctx t in
				let r = alloc_tmp ctx t in
				(match t with
				| HI8 | HI16 | HI32 ->
					op ctx (OInt (r,alloc_i32 ctx 0l))
				| HF32 | HF64 ->
					op ctx (OFloat (r, alloc_float ctx 0.))
				| t ->
					error ("Unsupported basic type " ^ tstr t) e.epos);
				r
			| _ ->
				error "Invalid BytesAccess" eb.epos);
		| "$bget", [eb;pos] ->
			(match follow eb.etype with
			| TAbstract({a_path = ["hl";"types"],"BytesAccess"},[t]) ->
				let b = eval_to ctx eb HBytes in
				let pos = eval_to ctx pos HI32 in
				let t = to_type ctx t in
				(match t with
				| HI8 ->
					let r = alloc_tmp ctx HI32 in
					op ctx (OGetI8 (r, b, pos));
					r
				| HI32 ->
					let r = alloc_tmp ctx HI32 in
					op ctx (OGetI32 (r, b, shl ctx pos 2));
					r
				| HF32 ->
					let r = alloc_tmp ctx HF32 in
					op ctx (OGetF32 (r, b, shl ctx pos 2));
					r
				| HF64 ->
					let r = alloc_tmp ctx HF64 in
					op ctx (OGetF64 (r, b, shl ctx pos 3));
					r
				| _ ->
					error ("Unsupported basic type " ^ tstr t) e.epos)
			| _ ->
				error "Invalid BytesAccess" eb.epos);
		| "$bset", [eb;pos;value] ->
			(match follow eb.etype with
			| TAbstract({a_path = ["hl";"types"],"BytesAccess"},[t]) ->
				let b = eval_to ctx eb HBytes in
				let pos = eval_to ctx pos HI32 in
				let t = to_type ctx t in
				(match t with
				| HI8 ->
					let v = eval_to ctx value HI32 in
					op ctx (OSetI8 (b, pos, v));
					v
				| HI32 ->
					let v = eval_to ctx value HI32 in
					op ctx (OSetI32 (b, shl ctx pos 2, v));
					v
				| HF32 ->
					let v = eval_to ctx value HF32 in
					op ctx (OSetF32 (b, shl ctx pos 2, v));
					v
				| HF64 ->
					let v = eval_to ctx value HF64 in
					op ctx (OSetF64 (b, shl ctx pos 3, v));
					v
				| _ ->
					error ("Unsupported basic type " ^ tstr t) e.epos)
			| _ ->
				error "Invalid BytesAccess" eb.epos);
		| "$bgeti8", [b;pos] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = alloc_tmp ctx HI32 in
			op ctx (OGetI8 (r, b, pos));
			r
		| "$bgeti32", [b;pos] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = alloc_tmp ctx HI32 in
			op ctx (OGetI32 (r, b, pos));
			r
		| "$bgetf32", [b;pos] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = alloc_tmp ctx HF32 in
			op ctx (OGetF32 (r, b, pos));
			r
		| "$bgetf64", [b;pos] ->
			let b = eval_to ctx b HBytes in
			let pos = eval_to ctx pos HI32 in
			let r = alloc_tmp ctx HF64 in
			op ctx (OGetF64 (r, b, pos));
			r
		| "$asize", [e] ->
			let r = alloc_tmp ctx HI32 in
			op ctx (OArraySize (r, eval_to ctx e HArray));
			r
		| "$aalloc", [esize] ->
			let et = (match follow e.etype with TAbstract ({ a_path = ["hl";"types"],"NativeArray" },[t]) -> to_type ctx t | _ -> invalid()) in
			let a = alloc_tmp ctx HArray in
			let rt = alloc_tmp ctx HType in
			op ctx (OType (rt,et));
			let size = eval_to ctx esize HI32 in
			op ctx (OCall2 (a,alloc_std ctx "aalloc" [HType;HI32] HArray,rt,size));
			a
		| "$aget", [a; pos] ->
			(*
				read/write on arrays are unsafe : the type of NativeArray needs to be correcly set.
			*)
			let at = (match follow a.etype with TAbstract ({ a_path = ["hl";"types"],"NativeArray" },[t]) -> to_type ctx t | _ -> invalid()) in
			let arr = eval_to ctx a HArray in
			let pos = eval_to ctx pos HI32 in
			let r = alloc_tmp ctx at in
			op ctx (OGetArray (r, arr, pos));
			cast_to ctx r (to_type ctx e.etype) e.epos
		| "$aset", [a; pos; value] ->
			let et = (match follow a.etype with TAbstract ({ a_path = ["hl";"types"],"NativeArray" },[t]) -> to_type ctx t | _ -> invalid()) in
			let arr = eval_to ctx a HArray in
			let pos = eval_to ctx pos HI32 in
			let r = eval_to ctx value et in
			op ctx (OSetArray (arr, pos, r));
			r
		| "$ref", [{ eexpr = TLocal v }] ->
			let r = alloc_tmp ctx (to_type ctx e.etype) in
			let rv = (match rtype ctx r with HRef t -> alloc_reg ctx v | _ -> invalid()) in
			op ctx (ORef (r,rv));
			r
		| "$ttype", [v] ->
			let r = alloc_tmp ctx HType in
			op ctx (OType (r,to_type ctx v.etype));
			r
		| "$tdyntype", [v] ->
			let r = alloc_tmp ctx HType in
			op ctx (OGetType (r,eval_to ctx v HDyn));
			r
		| "$tkind", [v] ->
			let r = alloc_tmp ctx HI32 in
			op ctx (OGetTID (r,eval_to ctx v HType));
			r
		| "$dump", [v] ->
			op ctx (ODump (eval_expr ctx v));
			alloc_tmp ctx HVoid
		| ("$is" | "$instance") as name, [v;t] ->
			let v = eval_to ctx v HDyn in
			let t = (match t.eexpr with
			| TTypeExpr t ->
				let r = alloc_tmp ctx HType in
				let t = (match t with
				| TClassDecl { cl_path = [],"Array" } -> TInst (ctx.array_impl.aall,[])
				| TClassDecl c -> TInst (c,List.map (fun _ -> t_dynamic) c.cl_params)
				| TEnumDecl e -> TEnum (e,List.map (fun _ -> t_dynamic) e.e_params)
				| TAbstractDecl a -> TAbstract (a,List.map (fun _ -> t_dynamic) a.a_params)
				| TTypeDecl t -> TType (t, List.map (fun _ -> t_dynamic) t.t_params)
				) in
				op ctx (OType (r,to_type ctx t));
				r
			| _ ->
				let r = eval_to ctx t (class_type ctx ctx.base_type [] false) in
				let t = alloc_tmp ctx HType in
				op ctx (OJNotNull (r,2));
				op ctx (OType (t,HVoid));
				op ctx (OJAlways 1);
				op ctx (OField (t,r,0));
				t
			) in
			if name = "$instance" then begin
				let tmp = alloc_tmp ctx HDyn in
				let r = alloc_tmp ctx (to_type ctx e.etype) in
				op ctx (OCall2 (tmp,alloc_std ctx "type_instance" [HType;HDyn] HDyn,t,v));
				op ctx (OUnsafeCast (r, tmp));
				r
			end else begin
				let r = alloc_tmp ctx HBool in
				op ctx (OCall2 (r,alloc_std ctx "type_check" [HType;HDyn] HBool,t,v));
				r
			end
		| "$resources", [] ->
			let tdef = (try List.find (fun t -> (t_infos t).mt_path = (["haxe";"_Resource"],"ResourceContent")) ctx.com.types with Not_found -> assert false) in
			let t = class_type ctx (match tdef with TClassDecl c -> c | _ -> assert false) [] false in
			let arr = alloc_tmp ctx HArray in
			let rt = alloc_tmp ctx HType in
			op ctx (OType (rt,t));
			let res = Hashtbl.fold (fun k v acc -> (k,v) :: acc) ctx.com.resources [] in
			let size = reg_int ctx (List.length res) in
			op ctx (OCall2 (arr,alloc_std ctx "aalloc" [HType;HI32] HArray,rt,size));
			let ro = alloc_tmp ctx t in
			let rb = alloc_tmp ctx HBytes in
			let ridx = reg_int ctx 0 in
			iteri (fun i (k,v) ->
				op ctx (ONew ro);
				op ctx (OString (rb,alloc_string ctx k));
				op ctx (OSetField (ro,0,rb));
				op ctx (OBytes (rb,alloc_string ctx v));
				op ctx (OSetField (ro,1,rb));
				op ctx (OSetField (ro,2,reg_int ctx (String.length v)));
				op ctx (OSetArray (arr,ridx,ro));
				op ctx (OIncr ridx);
			) res;
			arr
		| "$allTypes", [] ->
			let r = alloc_tmp ctx (to_type ctx e.etype) in
			op ctx (OGetGlobal (r, alloc_global ctx "__types__" (rtype ctx r)));
			r
		| "$allTypes", [v] ->
			let v = eval_expr ctx v in
			op ctx (OSetGlobal (alloc_global ctx "__types__" (rtype ctx v), v));
			v
		| "$hash", [v] ->
			(match v.eexpr with
			| TConst (TString str) ->
				let r = alloc_tmp ctx HI32 in
				op ctx (OInt (r,alloc_i32 ctx (hash str)));
				r
			| _ -> error "Constant string required" v.epos)
		| "$enumIndex", [v] ->
			let r = alloc_tmp ctx HI32 in
			let re = eval_expr ctx v in
			op ctx (ONullCheck re);
			op ctx (OEnumIndex (r,re));
			r
		| _ ->
			error ("Unknown native call " ^ v.v_name) e.epos)
	| TCall (ec,args) ->
		let tfun = real_type ctx ec in
		let el() = eval_args ctx args tfun e.epos in
		let ret = alloc_tmp ctx (match tfun with HFun (_,r) -> r | _ -> HDyn) in
		let def_ret = ref None in
		(match get_access ctx ec with
		| AStaticFun f ->
			(match el() with
			| [] -> op ctx (OCall0 (ret, f))
			| [a] -> op ctx (OCall1 (ret, f, a))
			| [a;b] -> op ctx (OCall2 (ret, f, a, b))
			| [a;b;c] -> op ctx (OCall3 (ret, f, a, b, c))
			| [a;b;c;d] -> op ctx (OCall4 (ret, f, a, b, c, d))
			| el -> op ctx (OCallN (ret, f, el)));
		| AInstanceFun (ethis, f) ->
			let el = eval_null_check ctx ethis :: el() in
			(match el with
			| [a] -> op ctx (OCall1 (ret, f, a))
			| [a;b] -> op ctx (OCall2 (ret, f, a, b))
			| [a;b;c] -> op ctx (OCall3 (ret, f, a, b, c))
			| [a;b;c;d] -> op ctx (OCall4 (ret, f, a, b, c, d))
			| _ -> op ctx (OCallN (ret, f, el)));
		| AInstanceProto ({ eexpr = TConst TThis }, fid) ->
			op ctx (OCallThis (ret, fid, el()))
		| AInstanceProto (ethis, fid) ->
			let el = eval_null_check ctx ethis :: el() in
			op ctx (OCallMethod (ret, fid, el))
		| AEnum index ->
			op ctx (OMakeEnum (ret, index, el()))
		| AArray (a,t,idx) ->
			let r = array_read ctx a t idx ec.epos in
			op ctx (ONullCheck r);
			op ctx (OCallClosure (ret, r, el())); (* if it's a value, it's a closure *)
		| _ ->
			let r = eval_null_check ctx ec in
			(* don't use real_type here *)
			let tfun = to_type ctx ec.etype in
			let el() = eval_args ctx args tfun e.epos in
			let ret = alloc_tmp ctx (match tfun with HFun (_,r) -> r | _ -> HDyn) in
			op ctx (OCallClosure (ret, r, el())); (* if it's a value, it's a closure *)
			def_ret := Some (unsafe_cast_to ctx ret (to_type ctx e.etype) e.epos);
		);
		(match !def_ret with None -> unsafe_cast_to ctx ret (to_type ctx e.etype) e.epos | Some r -> r)
	| TField (ec,FInstance({ cl_path = [],"Array" },[t],{ cf_name = "length" })) when to_type ctx t = HDyn ->
		let r = alloc_tmp ctx HI32 in
		op ctx (OCall1 (r,alloc_fun_path ctx (["hl";"types"],"ArrayDyn") "get_length", eval_null_check ctx ec));
		r
	| TField (ec,a) ->
		let r = alloc_tmp ctx (to_type ctx (field_type ctx a e.epos)) in
		(match get_access ctx e with
		| AGlobal g ->
			op ctx (OGetGlobal (r,g));
		| AStaticVar (g,t,fid) ->
			let o = alloc_tmp ctx t in
			op ctx (OGetGlobal (o,g));
			op ctx (OField (r,o,fid));
		| AStaticFun f ->
			op ctx (OGetFunction (r,f));
		| AInstanceFun (ethis, f) ->
			op ctx (OClosure (r, f, eval_null_check ctx ethis))
		| AInstanceField (ethis,fid) ->
			let robj = eval_null_check ctx ethis in
			op ctx (match ethis.eexpr with TConst TThis -> OGetThis (r,fid) | _ -> OField (r,robj,fid));
		| AInstanceProto (ethis,fid) | AVirtualMethod (ethis, fid) ->
			let robj = eval_null_check ctx ethis in
			op ctx (OMethod (r,robj,fid));
		| ADynamic (ethis, f) ->
			let robj = eval_null_check ctx ethis in
			op ctx (ODynGet (r,robj,f))
		| AEnum index ->
			op ctx (OMakeEnum (r,index,[]))
		| ANone | ALocal _ | AArray _ | ACaptured _ ->
			error "Invalid access" e.epos);
		unsafe_cast_to ctx r (to_type ctx e.etype) e.epos
	| TObjectDecl o ->
		let r = alloc_tmp ctx HDynObj in
		op ctx (ONew r);
		let a = (match follow e.etype with TAnon a -> Some a | t -> if t == t_dynamic then None else assert false) in
		List.iter (fun (s,v) ->
			let ft = (try (match a with None -> raise Not_found | Some a -> PMap.find s a.a_fields).cf_type with Not_found -> v.etype) in
			let v = eval_to ctx v (to_type ctx ft) in
			op ctx (ODynSet (r,alloc_string ctx s,v));
			if s = "toString" then begin
				let f = alloc_tmp ctx (HFun ([],HBytes)) in
				op ctx (OClosure (f, alloc_fun_path ctx ([],"String") "call_toString", r));
				op ctx (ODynSet (r,alloc_string ctx "__string",f));
			end;
		) o;
		cast_to ctx r (to_type ctx e.etype) e.epos
	| TNew (c,pl,el) ->
		let c = resolve_class ctx c pl false in
		let r = alloc_tmp ctx (class_type ctx c pl false) in
		op ctx (ONew r);
		(match c.cl_constructor with
		| None -> ()
		| Some { cf_expr = None } -> error (s_type_path c.cl_path ^ " does not have a constructor") e.epos
		| Some ({ cf_expr = Some cexpr } as constr) ->
			let rl = eval_args ctx el (to_type ctx cexpr.etype) e.epos in
			let ret = alloc_tmp ctx HVoid in
			let g = alloc_fid ctx c constr in
			op ctx (match rl with
			| [] -> OCall1 (ret,g,r)
			| [a] -> OCall2 (ret,g,r,a)
			| [a;b] -> OCall3 (ret,g,r,a,b)
			| [a;b;c] -> OCall4 (ret,g,r,a,b,c)
			| _ -> OCallN (ret,g,r :: rl));
		);
		r
	| TIf (cond,eif,eelse) ->
		let t = to_type ctx e.etype in
		let out = alloc_tmp ctx t in
		let j = jump_expr ctx cond false in
		if t = HVoid then ignore(eval_expr ctx eif) else op ctx (OMov (out,eval_to ctx eif t));
		(match eelse with
		| None -> j()
		| Some e ->
			let jexit = jump ctx (fun i -> OJAlways i) in
			j();
			if t = HVoid then ignore(eval_expr ctx e) else op ctx (OMov (out,eval_to ctx e t));
			jexit());
		out
	| TBinop (bop, e1, e2) ->
		let is_unsigned() = unsigned e1.etype && unsigned e2.etype in
		let boolop r f =
			let j = jump ctx f in
			op ctx (OBool (r,false));
			op ctx (OJAlways 1);
			j();
			op ctx (OBool (r, true));
		in
		let binop r a b =
			let rec loop bop =
				match bop with
				| OpLte -> boolop r (fun d -> if is_unsigned() then OJUGte (b,a,d) else OJSLte (a,b,d))
				| OpGt -> boolop r (fun d -> if is_unsigned() then OJULt (b,a,d) else OJSGt (a,b,d))
				| OpGte -> boolop r (fun d -> if is_unsigned() then OJUGte (a,b,d) else OJSGte (a,b,d))
				| OpLt -> boolop r (fun d -> if is_unsigned() then OJULt (a,b,d) else OJSLt (a,b,d))
				| OpEq -> boolop r (fun d -> OJEq (a,b,d))
				| OpNotEq -> boolop r (fun d -> OJNotEq (a,b,d))
				| OpAdd ->
					(match rtype ctx r with
					| HI8 | HI16 | HI32 | HF32 | HF64 ->
						op ctx (OAdd (r,a,b))
					| HObj { pname = "String" } ->
						op ctx (OCall2 (r,alloc_fun_path ctx ([],"String") "__add__",a,b))
					| HDyn ->
						op ctx (OCall2 (r,alloc_fun_path ctx ([],"Std") "__add__",a,b))
					| t ->
						error ("Cannot add " ^ tstr t) e.epos)
				| OpSub | OpMult | OpMod | OpDiv ->
					(match rtype ctx r with
					| HI8 | HI16 | HI32 | HF32 | HF64 ->
						(match bop with
						| OpSub -> op ctx (OSub (r,a,b))
						| OpMult -> op ctx (OMul (r,a,b))
						| OpMod -> op ctx (if is_unsigned() then OUMod (r,a,b) else OSMod (r,a,b))
						| OpDiv -> op ctx (OSDiv (r,a,b)) (* don't use UDiv since both operands are float already *)
						| _ -> assert false)
					| _ ->
						assert false)
				| OpShl | OpShr | OpUShr | OpAnd | OpOr | OpXor ->
					(match rtype ctx r with
					| HI8 | HI16 | HI32 ->
						(match bop with
						| OpShl -> op ctx (OShl (r,a,b))
						| OpShr -> op ctx (if unsigned e1.etype then OUShr (r,a,b) else OSShr (r,a,b))
						| OpUShr -> op ctx (OUShr (r,a,b))
						| OpAnd -> op ctx (OAnd (r,a,b))
						| OpOr -> op ctx (OOr (r,a,b))
						| OpXor -> op ctx (OXor (r,a,b))
						| _ -> ())
					| _ ->
						assert false)
				| OpAssignOp bop ->
					loop bop
				| _ ->
					assert false
			in
			loop bop
		in
		(match bop with
		| OpLte | OpGt | OpGte | OpLt ->
			let r = alloc_tmp ctx HBool in
			let t = common_type ctx e1 e2 false e.epos in
			let a = eval_to ctx e1 t in
			let b = eval_to ctx e2 t in
			binop r a b;
			r
		| OpEq | OpNotEq ->
			let r = alloc_tmp ctx HBool in
			let t = common_type ctx e1 e2 true e.epos in
			let a = eval_to ctx e1 t in
			let b = eval_to ctx e2 t in
			binop r a b;
			r
		| OpAdd | OpSub | OpMult | OpDiv | OpMod | OpShl | OpShr | OpUShr | OpAnd | OpOr | OpXor ->
			let t = (match to_type ctx e.etype with HNull t -> t | t -> t) in
			let r = alloc_tmp ctx t in
			let a = eval_to ctx e1 t in
			let b = eval_to ctx e2 t in
			binop r a b;
			r
		| OpAssign ->
			let value() = eval_to ctx e2 (real_type ctx e1) in
			(match get_access ctx e1 with
			| AGlobal g ->
				let r = value() in
				op ctx (OSetGlobal (g,r));
				r
			| AStaticVar (g,t,fid) ->
				let r = value() in
				let o = alloc_tmp ctx t in
				op ctx (OGetGlobal (o, g));
				op ctx (OSetField (o, fid, r));
				r
			| AInstanceField ({ eexpr = TConst TThis }, fid) ->
				let r = value() in
				op ctx (OSetThis (fid,r));
				r
			| AInstanceField (ethis, fid) ->
				let rthis = eval_null_check ctx ethis in
				let r = value() in
				op ctx (OSetField (rthis, fid, r));
				r
			| ALocal l ->
				let r = value() in
				op ctx (OMov (l, r));
				r
			| AArray (ra,(at,vt),ridx) ->
				let v = cast_to ctx (value()) at e.epos in
				(* bounds check against length *)
				(match at with
				| HDyn ->
					(* call setDyn() *)
					op ctx (OCallMethod (alloc_tmp ctx HVoid,1,[ra;ridx;cast_to ctx v (if is_dynamic at then at else HDyn) e.epos]));
				| _ ->
					let len = alloc_tmp ctx HI32 in
					op ctx (OField (len,ra,0)); (* length *)
					let j = jump ctx (fun i -> OJULt (ridx,len,i)) in
					op ctx (OCall2 (alloc_tmp ctx HVoid, alloc_fun_path ctx (array_class ctx at).cl_path "__expand", ra, ridx));
					j();
					match at with
					| HI32 | HF64 ->
						let b = alloc_tmp ctx HBytes in
						op ctx (OField (b,ra,1));
						write_mem ctx b (shl ctx ridx (type_size_bits at)) at v
					| _ ->
						let arr = alloc_tmp ctx HArray in
						op ctx (OField (arr,ra,1));
						op ctx (OSetArray (arr,ridx,cast_to ctx v (if is_dynamic at then at else HDyn) e.epos))
				);
				v
			| ADynamic (ethis,f) ->
				let obj = eval_null_check ctx ethis in
				let r = eval_expr ctx e2 in
				op ctx (ODynSet (obj,f,r));
				r
			| ACaptured index ->
				let r = value() in
				op ctx (OSetEnumField (ctx.m.mcaptreg,index,r));
				r
			| AEnum _ | ANone | AInstanceFun _ | AInstanceProto _ | AStaticFun _ | AVirtualMethod _ ->
				assert false)
		| OpBoolOr ->
			let r = alloc_tmp ctx HBool in
			let j = jump_expr ctx e1 true in
			let j2 = jump_expr ctx e2 true in
			op ctx (OBool (r,false));
			let jend = jump ctx (fun b -> OJAlways b) in
			j();
			j2();
			op ctx (OBool (r,true));
			jend();
			r
		| OpBoolAnd ->
			let r = alloc_tmp ctx HBool in
			let j = jump_expr ctx e1 false in
			let j2 = jump_expr ctx e2 false in
			op ctx (OBool (r,true));
			let jend = jump ctx (fun b -> OJAlways b) in
			j();
			j2();
			op ctx (OBool (r,false));
			jend();
			r
		| OpAssignOp bop ->
			(match get_access ctx e1 with
			| ALocal l ->
				let r = eval_to ctx { e with eexpr = TBinop (bop,e1,e2) } (to_type ctx e1.etype) in
				op ctx (OMov (l, r));
				r
			| acc ->
				gen_assign_op ctx acc e1 (fun r ->
					let b = eval_to ctx e2 (rtype ctx r) in
					binop r r b;
					r))
		| OpInterval | OpArrow ->
			assert false)
	| TUnop (Not,_,v) ->
		let tmp = alloc_tmp ctx HBool in
		let r = eval_to ctx v HBool in
		op ctx (ONot (tmp,r));
		tmp
	| TUnop (Neg,_,v) ->
		let t = to_type ctx e.etype in
		let tmp = alloc_tmp ctx t in
		let r = eval_to ctx v t in
		op ctx (ONeg (tmp,r));
		tmp
	| TUnop (NegBits,_,v) ->
		let t = to_type ctx e.etype in
		let tmp = alloc_tmp ctx t in
		let r = eval_to ctx v t in
		let mask = (match t with
			| HI8 -> 0xFFl
			| HI16 -> 0xFFFFl
			| HI32 -> 0xFFFFFFFFl
			| _ -> error (tstr t) e.epos
		) in
		let r2 = alloc_tmp ctx t in
		op ctx (OInt (r2,alloc_i32 ctx mask));
		op ctx (OXor (tmp,r,r2));
		tmp
	| TUnop (Increment|Decrement as uop,fix,v) ->
		let rec unop r =
			match rtype ctx r with
			| HI8 | HI16 | HI32 ->
				if uop = Increment then op ctx (OIncr r) else op ctx (ODecr r)
			| HF32 | HF64 as t ->
				let tmp = alloc_tmp ctx t in
				op ctx (OFloat (tmp,alloc_float ctx 1.));
				if uop = Increment then op ctx (OAdd (r,r,tmp)) else op ctx (OSub (r,r,tmp))
			| HNull (HI8 | HI16 | HI32 | HF32 | HF64 as t) ->
				let tmp = alloc_tmp ctx t in
				op ctx (OSafeCast (tmp,r));
				unop tmp;
				op ctx (OToDyn (r,tmp));
			| _ ->
				assert false
		in
		(match get_access ctx v, fix with
		| ALocal r, Prefix ->
			unop r;
			r
		| ALocal r, Postfix ->
			let r2 = alloc_tmp ctx (rtype ctx r) in
			op ctx (OMov (r2,r));
			unop r;
			r2
		| acc, _ ->
			let ret = ref 0 in
			ignore(gen_assign_op ctx acc v (fun r ->
				if fix = Prefix then ret := r else begin
					let tmp = alloc_tmp ctx (rtype ctx r) in
					op ctx (OMov (tmp, r));
					ret := tmp;
				end;
				unop r;
				r)
			);
			!ret)
	| TFunction f ->
		let fid = alloc_function_name ctx ("function#" ^ string_of_int (DynArray.length ctx.cfids.arr)) in
		let capt = make_fun ctx fid f None (Some ctx.m.mcaptured) in
		let r = alloc_tmp ctx (to_type ctx e.etype) in
		if capt == ctx.m.mcaptured then
			op ctx (OClosure (r, fid, ctx.m.mcaptreg))
		else if Array.length capt.c_vars > 0 then
			let env = alloc_tmp ctx capt.c_type in
			op ctx (OEnumAlloc (env,0));
			Array.iteri (fun i v ->
				let r = (match captured_index ctx v with
				| None -> alloc_reg ctx v
				| Some idx ->
					let r = alloc_tmp ctx (to_type ctx v.v_type) in
					op ctx (OEnumField (r,ctx.m.mcaptreg,0,idx));
					r
				) in
				op ctx (OSetEnumField (env,i,r));
			) capt.c_vars;
			op ctx (OClosure (r, fid, env))
		else
			op ctx (OGetFunction (r, fid));
		r
	| TThrow v ->
		op ctx (OThrow (eval_to ctx v HDyn));
		alloc_tmp ctx HVoid
	| TWhile (cond,eloop,NormalWhile) ->
		let oldb = ctx.m.mbreaks and oldc = ctx.m.mcontinues in
		ctx.m.mbreaks <- [];
		ctx.m.mcontinues <- [];
		let continue_pos = current_pos ctx in
		let ret = jump_back ctx in
		let j = jump_expr ctx cond false in
		ignore(eval_expr ctx eloop);
		ret();
		j();
		List.iter (fun f -> f (current_pos ctx)) ctx.m.mbreaks;
		List.iter (fun f -> f continue_pos) ctx.m.mcontinues;
		ctx.m.mbreaks <- oldb;
		ctx.m.mcontinues <- oldc;
		alloc_tmp ctx HVoid
	| TWhile (cond,eloop,DoWhile) ->
		let oldb = ctx.m.mbreaks and oldc = ctx.m.mcontinues in
		ctx.m.mbreaks <- [];
		ctx.m.mcontinues <- [];
		let start = jump ctx (fun p -> OJAlways p) in
		let continue_pos = current_pos ctx in
		let ret = jump_back ctx in
		let j = jump_expr ctx cond false in
		start();
		ignore(eval_expr ctx eloop);
		ret();
		j();
		List.iter (fun f -> f (current_pos ctx)) ctx.m.mbreaks;
		List.iter (fun f -> f continue_pos) ctx.m.mcontinues;
		ctx.m.mbreaks <- oldb;
		ctx.m.mcontinues <- oldc;
		alloc_tmp ctx HVoid
	| TCast (v,None) ->
		let t = to_type ctx e.etype in
		let rv = eval_expr ctx v in
		(match t with
		| HF32 | HF64 when unsigned v.etype ->
			let r = alloc_tmp ctx t in
			op ctx (OToUFloat (r,rv));
			r
		| _ ->
			cast_to ~force:true ctx rv t e.epos)
	| TArrayDecl el ->
		let r = alloc_tmp ctx (to_type ctx e.etype) in
		let et = (match follow e.etype with TInst (_,[t]) -> to_type ctx t | _ -> assert false) in
		(match et with
		| HI32 ->
			let b = alloc_tmp ctx HBytes in
			let size = reg_int ctx ((List.length el) * 4) in
			op ctx (OCall1 (b,alloc_std ctx "balloc" [HI32] HBytes,size));
			list_iteri (fun i e ->
				let r = eval_to ctx e HI32 in
				op ctx (OSetI32 (b,reg_int ctx (i * 4),r));
			) el;
			op ctx (OCall2 (r, alloc_fun_path ctx (["hl";"types"],"ArrayBase") "allocI32", b, reg_int ctx (List.length el)));
		| HF64 ->
			let b = alloc_tmp ctx HBytes in
			let size = reg_int ctx ((List.length el) * 8) in
			op ctx (OCall1 (b,alloc_std ctx "balloc" [HI32] HBytes,size));
			list_iteri (fun i e ->
				let r = eval_to ctx e HF64 in
				op ctx (OSetF64 (b,reg_int ctx (i * 8),r));
			) el;
			op ctx (OCall2 (r, alloc_fun_path ctx (["hl";"types"],"ArrayBase") "allocF64", b, reg_int ctx (List.length el)));
		| _ ->
			let at = if is_dynamic et then et else HDyn in
			let a = alloc_tmp ctx HArray in
			let rt = alloc_tmp ctx HType in
			op ctx (OType (rt,at));
			let size = reg_int ctx (List.length el) in
			op ctx (OCall2 (a,alloc_std ctx "aalloc" [HType;HI32] HArray,rt,size));
			list_iteri (fun i e ->
				let r = eval_to ctx e at in
				op ctx (OSetArray (a,reg_int ctx i,r));
			) el;
			let tmp = if et = HDyn then alloc_tmp ctx (class_type ctx ctx.array_impl.aobj [] false) else r in
			op ctx (OCall1 (tmp, alloc_fun_path ctx (["hl";"types"],"ArrayObj") "alloc", a));
			if tmp <> r then begin
				let re = alloc_tmp ctx HBool in
				op ctx (OBool (re,true));
				let ren = alloc_tmp ctx (HNull HBool) in
				op ctx (OToDyn (ren, re));
				op ctx (OCall2 (r, alloc_fun_path ctx (["hl";"types"],"ArrayDyn") "alloc", tmp, ren));
			end;
		);
		r
	| TArray _ ->
		(match get_access ctx e with
		| AArray (a,at,idx) ->
			array_read ctx a at idx e.epos
		| _ ->
			assert false)
	| TMeta (_,e) ->
		eval_expr ctx e
	| TFor _ ->
		assert false (* eliminated with pf_for_to_while *)
	| TSwitch (en,cases,def) ->
		let rt = to_type ctx e.etype in
		let r = alloc_tmp ctx rt in
		(try
			let max = ref (-1) in
			let rec get_int e =
				match e.eexpr with
				| TConst (TInt i) ->
					let v = Int32.to_int i in
					if Int32.of_int v <> i then raise Exit;
					v
				| _ ->
					raise Exit
			in
			List.iter (fun (values,_) ->
				List.iter (fun v ->
					let i = get_int v in
					if i < 0 then raise Exit;
					if i > !max then max := i;
				) values;
			) cases;
			if !max > 255 || cases = [] then raise Exit;
			let ridx = eval_to ctx en HI32 in
			let indexes = Array.make (!max + 1) 0 in
			op ctx (OSwitch (ridx,indexes));
			let switch_pos = current_pos ctx in
			(match def with
			| None ->
				if rt <> HVoid then op ctx (ONull r);
			| Some e ->
				let re = eval_to ctx e rt in
				if rt <> HVoid then op ctx (OMov (r,re)));
			let jends = ref [jump ctx (fun i -> OJAlways i)] in
			List.iter (fun (values,ecase) ->
				List.iter (fun v ->
					Array.set indexes (get_int v) (current_pos ctx - switch_pos)
				) values;
				let re = eval_to ctx ecase rt in
				op ctx (OMov (r,re));
				jends := jump ctx (fun i -> OJAlways i) :: !jends
			) cases;
			List.iter (fun j -> j()) (!jends);
		with Exit ->
			let jends = ref [] in
			let rvalue = eval_expr ctx en in
			let loop (cases,e) =
				let ok = List.map (fun c ->
					let r = eval_to ctx c (common_type ctx en c true c.epos) in
					jump ctx (fun n -> OJEq (r,rvalue,n))
				) cases in
				(fun() ->
					List.iter (fun f -> f()) ok;
					let re = eval_to ctx e rt in
					if rt <> HVoid then op ctx (OMov (r,re));
					jends := jump ctx (fun n -> OJAlways n) :: !jends)
			in
			let all = List.map loop cases in
			(match def with
			| None ->
				if rt <> HVoid then op ctx (ONull r)
			| Some e ->
				let rdef = eval_to ctx e rt in
				if rt <> HVoid then op ctx (OMov (r,rdef)));
			jends := jump ctx (fun n -> OJAlways n) :: !jends;
			List.iter (fun f -> f()) all;
			List.iter (fun j -> j()) (!jends);
		);
		r
	| TEnumParameter (ec,f,index) ->
		(* TODO: See what we can do about this in matcher.ml (see #4846) *)
		let ec = match follow ec.etype,follow f.ef_type with
			| TEnum _,_ -> ec
			| _,(TEnum _ as t | TFun(_,t)) -> mk (TCast(ec,None)) t ec.epos
			| _ -> assert false
		in
		let r = alloc_tmp ctx (match to_type ctx ec.etype with HEnum e -> let _,_,args = e.efields.(f.ef_index) in args.(index) | _ -> assert false) in
		op ctx (OEnumField (r,eval_expr ctx ec,f.ef_index,index));
		cast_to ctx r (to_type ctx e.etype) e.epos
	| TContinue ->
		let pos = current_pos ctx in
		op ctx (OJAlways (-1)); (* loop *)
		ctx.m.mcontinues <- (fun target -> DynArray.set ctx.m.mops pos (OJAlways (target - (pos + 1)))) :: ctx.m.mcontinues;
		alloc_tmp ctx HVoid
	| TBreak ->
		let pos = current_pos ctx in
		op ctx (OJAlways (-1)); (* loop *)
		ctx.m.mbreaks <- (fun target -> DynArray.set ctx.m.mops pos (OJAlways (target - (pos + 1)))) :: ctx.m.mbreaks;
		alloc_tmp ctx HVoid
	| TTry (etry,catches) ->
		let pos = current_pos ctx in
		let rtrap = alloc_tmp ctx HDyn in
		op ctx (OTrap (rtrap,-1)); (* loop *)
		ctx.m.mtrys <- ctx.m.mtrys + 1;
		let tret = to_type ctx e.etype in
		let result = alloc_tmp ctx tret in
		let r = eval_expr ctx etry in
		if tret <> HVoid then op ctx (OMov (result,cast_to ctx r tret etry.epos));
		ctx.m.mtrys <- ctx.m.mtrys - 1;
		op ctx (OEndTrap 0);
		let j = jump ctx (fun n -> OJAlways n) in
		DynArray.set ctx.m.mops pos (OTrap (rtrap, current_pos ctx - (pos + 1)));
		let rec loop l =
			match l with
			| [] ->
				op ctx (ORethrow rtrap);
				[]
			| (v,ec) :: next ->
				let rv = alloc_reg ctx v in
				let jnext = if v.v_type == t_dynamic then begin
					op ctx (OMov (rv, rtrap));
					(fun() -> ())
				end else
					let rb = alloc_tmp ctx HBool in
					let rt = alloc_tmp ctx HType in
					op ctx (OType (rt, to_type ctx v.v_type));
					op ctx (OCall2 (rb, alloc_std ctx "type_check" [HType;HDyn] HBool, rt, rtrap));
					let jnext = jump ctx (fun n -> OJFalse (rb,n)) in
					op ctx (OMov (rv, unsafe_cast_to ctx rtrap (to_type ctx v.v_type) ec.epos));
					jnext
				in
				let r = eval_expr ctx ec in
				if tret <> HVoid then op ctx (OMov (result,cast_to ctx r tret ec.epos));
				if v.v_type == t_dynamic then [] else
				let jend = jump ctx (fun n -> OJAlways n) in
				jnext();
				jend :: loop next
		in
		List.iter (fun j -> j()) (loop catches);
		j();
		result
	| TTypeExpr t ->
		(match t with
		| TClassDecl c ->
			let g, t = class_global ctx c in
			let r = alloc_tmp ctx t in
			op ctx (OGetGlobal (r, g));
			r
		| TAbstractDecl a ->
			let r = alloc_tmp ctx (class_type ctx ctx.base_type [] false) in
			(match a.a_path with
			| [], "Int" -> op ctx (OGetGlobal (r, alloc_global ctx "$Int" (rtype ctx r)))
			| [], "Float" -> op ctx (OGetGlobal (r, alloc_global ctx "$Float" (rtype ctx r)))
			| [], "Bool" -> op ctx (OGetGlobal (r, alloc_global ctx "$Bool" (rtype ctx r)))
			| [], "Class" -> op ctx (OGetGlobal (r, fst (class_global ctx ctx.base_class)))
			| [], "Enum" -> op ctx (OGetGlobal (r, fst (class_global ctx ctx.base_enum)))
			| [], "Dynamic" -> op ctx (OGetGlobal (r, alloc_global ctx "$Dynamic" (rtype ctx r)))
			| _ -> error ("Unsupported type value " ^ s_type_path (t_path t)) e.epos);
			r
		| TEnumDecl e ->
			let r = alloc_tmp ctx (enum_class ctx e) in
			let rt = rtype ctx r in
			op ctx (OGetGlobal (r, alloc_global ctx (match rt with HObj o -> o.pname | _ -> assert false) rt));
			r
		| TTypeDecl _ ->
			assert false);
	| TCast (ev,Some _) ->
		let t = to_type ctx e.etype in
		let re = eval_expr ctx ev in
		let r = alloc_tmp ctx t in
		if safe_cast (rtype ctx re) t then
			op ctx (OMov (r,re))
		else
			op ctx (OSafeCast (r,re));
		r
and gen_assign_op ctx acc e1 f =
	let f r =
		match rtype ctx r with
		| HNull t ->
			let r2 = alloc_tmp ctx t in
			op ctx (OSafeCast (r2,r));
			let r3 = alloc_tmp ctx (HNull t) in
			op ctx (OToDyn (r3,f r2));
			r3
		| _ ->
			f r
	in
	match acc with
	| AInstanceField (eobj, findex) ->
		let robj = eval_null_check ctx eobj in
		let t = real_type ctx e1 in
		let r = alloc_tmp ctx t in
		op ctx (OField (r,robj,findex));
		let r = cast_to ctx r (to_type ctx e1.etype) e1.epos in
		let r = f r in
		op ctx (OSetField (robj,findex,cast_to ctx r t e1.epos));
		r
	| AStaticVar (g,t,fid) ->
		let o = alloc_tmp ctx t in
		op ctx (OGetGlobal (o,g));
		let r = alloc_tmp ctx (to_type ctx e1.etype) in
		op ctx (OField (r,o,fid));
		let r = f r in
		op ctx (OSetField (o,fid,r));
		r
	| AGlobal g ->
		let r = alloc_tmp ctx (to_type ctx e1.etype) in
		op ctx (OGetGlobal (r,g));
		let r = f r in
		op ctx (OSetGlobal (g,r));
		r
	| ACaptured idx ->
		let r = alloc_tmp ctx (to_type ctx e1.etype) in
		op ctx (OEnumField (r, ctx.m.mcaptreg, 0, idx));
		let r = f r in
		op ctx (OSetEnumField (ctx.m.mcaptreg,idx,r));
		r
	| AArray (ra,(at,_),ridx) ->
		(match at with
		| HDyn ->
			(* call getDyn() *)
			let r = alloc_tmp ctx HDyn in
			op ctx (OCallMethod (r,0,[ra;ridx]));
			let r = f r in
			(* call setDyn() *)
			op ctx (OCallMethod (alloc_tmp ctx HVoid,1,[ra;ridx;r]));
			r
		| _ ->
			(* bounds check against length *)
			let len = alloc_tmp ctx HI32 in
			op ctx (OField (len,ra,0)); (* length *)
			let j = jump ctx (fun i -> OJULt (ridx,len,i)) in
			op ctx (OCall2 (alloc_tmp ctx HVoid, alloc_fun_path ctx (array_class ctx at).cl_path "__expand", ra, ridx));
			j();
			match at with
			| HI32 | HF64 ->
				let hbytes = alloc_tmp ctx HBytes in
				op ctx (OField (hbytes, ra, 1));
				let ridx = shl ctx ridx (type_size_bits at) in
				let r = alloc_tmp ctx at in
				read_mem ctx r hbytes ridx at;
				let r = f r in
				write_mem ctx hbytes ridx at r;
				r
			| _ ->
				let arr = alloc_tmp ctx HArray in
				op ctx (OField (arr,ra,1));
				let r = alloc_tmp ctx at in
				op ctx (OGetArray (r,arr,ridx));
				let r = f r in
				op ctx (OSetArray (arr,ridx,r));
				r
		)
	| _ ->
		error ("TODO " ^ s_expr (s_type (print_context())) e1) e1.epos

and build_capture_vars ctx f =
	let ignored_vars = ref PMap.empty in
	let used_vars = ref PMap.empty in
	(* get all captured vars in scope, ignore vars that are declared *)
	let decl_var v =
		if v.v_capture then ignored_vars := PMap.add v.v_id () !ignored_vars
	in
	let use_var v =
		if v.v_capture then used_vars := PMap.add v.v_id v !used_vars
	in
	let rec loop e =
		(match e.eexpr with
		| TLocal v ->
			use_var v;
		| TVar (v,_) ->
			decl_var v
		| TTry (_,catches) ->
			List.iter (fun (v,_) -> decl_var v) catches
		| TFunction f ->
			List.iter (fun (v,_) -> decl_var v) f.tf_args;
		| _ ->
			()
		);
		Type.iter loop e
	in
	List.iter (fun (v,_) -> decl_var v) f.tf_args;
	loop f.tf_expr;
	let cvars = Array.of_list (PMap.fold (fun v acc -> if PMap.mem v.v_id !ignored_vars then acc else v :: acc) !used_vars []) in
	Array.sort (fun v1 v2 -> v1.v_id - v2.v_id) cvars;
	let indexes = ref PMap.empty in
	Array.iteri (fun i v -> indexes := PMap.add v.v_id i !indexes) cvars;
	{
		c_map = !indexes;
		c_vars = cvars;
		c_type = HEnum {
			eglobal = 0;
			ename = "";
			eid = 0;
			efields = [|"",0,Array.map (fun v -> to_type ctx v.v_type) cvars|];
		};
	}

and gen_method_wrapper ctx rt t p =
	try
		PMap.find (rt,t) ctx.method_wrappers
	with Not_found ->
		let fid = lookup_alloc ctx.cfids () in
		ctx.method_wrappers <- PMap.add (rt,t) fid ctx.method_wrappers;
		let old = ctx.m in
		let targs, tret = (match t with HFun (args, ret) -> args, ret | _ -> assert false) in
		let iargs, iret = (match rt with HFun (args, ret) -> args, ret | _ -> assert false) in
		ctx.m <- method_context fid HDyn null_capture;
		let rfun = alloc_tmp ctx rt in
		let rargs = List.map (alloc_tmp ctx) targs in
		let rret = alloc_tmp ctx iret in
		op ctx (OCallClosure (rret,rfun,List.map2 (fun r t -> cast_to ctx r t p) rargs iargs));
		op ctx (ORet (cast_to ctx rret tret p));
		let f = {
			findex = fid;
			ftype = HFun (rt :: targs, tret);
			regs = DynArray.to_array ctx.m.mregs.arr;
			code = DynArray.to_array ctx.m.mops;
			debug = DynArray.to_array ctx.m.mdebug;
		} in
		ctx.m <- old;
		DynArray.add ctx.cfunctions f;
		fid

and make_fun ?gen_content ctx fidx f cthis cparent =
	let old = ctx.m in
	let capt = build_capture_vars ctx f in
	let has_captured_vars = Array.length capt.c_vars > 0 in
	let capt, use_parent_capture = (match cparent with
		| Some cparent when has_captured_vars && List.for_all (fun v -> PMap.mem v.v_id cparent.c_map) (Array.to_list capt.c_vars) -> cparent, true
		| _ -> capt, false
	) in

	ctx.m <- method_context fidx (to_type ctx f.tf_type) capt;

	set_curpos ctx f.tf_expr.epos;

	let tthis = (match cthis with
	| None -> None
	| Some c ->
		let t = to_type ctx (TInst (c,[])) in
		ignore(alloc_tmp ctx t); (* index 0 *)
		Some t
	) in

	let rcapt = if has_captured_vars && cparent <> None then Some (alloc_tmp ctx capt.c_type) else None in

	let args = List.map (fun (v,o) ->
		let r = alloc_reg ctx (if o = None then v else { v with v_type = ctx.com.basic.tnull v.v_type }) in
		rtype ctx r
	) f.tf_args in

	if has_captured_vars then ctx.m.mcaptreg <- (match rcapt with
		| None ->
			let r = alloc_tmp ctx capt.c_type in
			op ctx (OEnumAlloc (r,0));
			r
		| Some r -> r
	);

	List.iter (fun (v, o) ->
		let r = alloc_reg ctx v in
		(match o with
		| None | Some TNull -> ()
		| Some c ->
			let j = jump ctx (fun n -> OJNotNull (r,n)) in
			(match c with
			| TNull | TThis | TSuper -> assert false
			| TInt i when (match to_type ctx (follow v.v_type) with HI8 | HI16 | HI32 | HDyn -> true | _ -> false) ->
				let tmp = alloc_tmp ctx HI32 in
				op ctx (OInt (tmp, alloc_i32 ctx i));
				op ctx (OToDyn (r, tmp));
			| TFloat s when (match to_type ctx (follow v.v_type) with HI8 | HI16 | HI32 -> true | _ -> false) ->
				let tmp = alloc_tmp ctx HI32 in
				op ctx (OInt (tmp, alloc_i32 ctx (Int32.of_float (float_of_string s))));
				op ctx (OToDyn (r, tmp));
			| TInt i ->
				let tmp = alloc_tmp ctx HF64 in
				op ctx (OFloat (tmp, alloc_float ctx (Int32.to_float i)));
				op ctx (OToDyn (r, tmp));
			| TFloat s ->
				let tmp = alloc_tmp ctx HF64 in
				op ctx (OFloat (tmp, alloc_float ctx (float_of_string s)));
				op ctx (OToDyn (r, tmp));
			| TBool b ->
				let tmp = alloc_tmp ctx HBool in
				op ctx (OBool (tmp, b));
				op ctx (OToDyn (r, tmp));
			| TString s ->
				let str, len = to_utf8 s f.tf_expr.epos in
				let rb = alloc_tmp ctx HBytes in
				op ctx (ONew r);
				op ctx (OString (rb,alloc_string ctx str));
				op ctx (OSetField (r,0,rb));
				op ctx (OSetField (r,1,reg_int ctx len));
			);
			j();
			(* if optional but not null, turn into a not nullable here *)
			let vt = to_type ctx v.v_type in
			if not (is_nullable vt) then begin
				let t = alloc_tmp ctx vt in
				ctx.m.mregs.map <- PMap.add v.v_id t ctx.m.mregs.map;
				op ctx (OSafeCast (t,r));
			end;
		);
		(match captured_index ctx v with
		| None -> ()
		| Some index ->
			op ctx (OSetEnumField (ctx.m.mcaptreg, index, alloc_reg ctx v)));
	) f.tf_args;

	(match gen_content with
	| None -> ()
	| Some f -> f());

	ignore(eval_expr ctx f.tf_expr);
	let tret = to_type ctx f.tf_type in
	let rec has_final_jump e =
		(* prevents a jump outside function bounds error *)
		match e.eexpr with
		| TBlock el -> (match List.rev el with e :: _ -> has_final_jump e | [] -> false)
		| TParenthesis e -> has_final_jump e
		| TReturn _ -> false
		| _ -> true
	in
	if tret = HVoid then
		op ctx (ORet (alloc_tmp ctx HVoid))
	else if has_final_jump f.tf_expr then begin
		let r = alloc_tmp ctx tret in
		(match tret with
		| HI32 | HI8 | HI16 -> op ctx (OInt (r,alloc_i32 ctx 0l))
		| HF32 | HF64 -> op ctx (OFloat (r,alloc_float ctx 0.))
		| HBool -> op ctx (OBool (r,false))
		| _ -> op ctx (ONull r));
		op ctx (ORet r)
	end;
	let fargs = (match tthis with None -> [] | Some t -> [t]) @ (match rcapt with None -> [] | Some r -> [rtype ctx r]) @ args in
	let f = {
		findex = fidx;
		ftype = HFun (fargs, tret);
		regs = DynArray.to_array ctx.m.mregs.arr;
		code = DynArray.to_array ctx.m.mops;
		debug = DynArray.to_array ctx.m.mdebug;
	} in
	ctx.m <- old;
	Hashtbl.add ctx.defined_funs fidx ();
	DynArray.add ctx.cfunctions f;
	capt

let generate_static ctx c f =
	match f.cf_kind with
	| Var _ ->
		()
	| Method m ->
		let add_native lib name =
			ignore(lookup ctx.cnatives (name ^ "@" ^ lib) (fun() ->
				let fid = alloc_fid ctx c f in
				Hashtbl.add ctx.defined_funs fid ();
				(alloc_string ctx lib, alloc_string ctx name,to_type ctx f.cf_type,fid)
			));
		in
		let rec loop = function
			| (Meta.Custom ":hlNative",[(EConst(String(lib)),_);(EConst(String(name)),_)] ,_ ) :: _ ->
				add_native lib name
			| (Meta.Custom ":hlNative",[(EConst(String(lib)),_)] ,_ ) :: _ ->
				add_native lib f.cf_name
			| (Meta.Custom ":hlNative",[] ,_ ) :: _ ->
				add_native "std" f.cf_name
			| (Meta.Custom ":hlNative",_ ,p) :: _ ->
				error "Invalid @:hlNative decl" p
			| [] ->
				ignore(make_fun ctx (alloc_fid ctx c f) (match f.cf_expr with Some { eexpr = TFunction f } -> f | _ -> assert false) None None)
			| _ :: l ->
				loop l
		in
		loop f.cf_meta


let rec generate_member ctx c f =
	match f.cf_kind with
	| Var _ -> ()
	| Method m ->
		let gen_content = if f.cf_name <> "new" then None else Some (fun() ->
			(*
				init dynamic functions
			*)
			List.iter (fun f ->
				match f.cf_kind with
				| Method MethDynamic ->
					let r = alloc_tmp ctx (to_type ctx f.cf_type) in
					let fid = (match class_type ctx c (List.map snd c.cl_params) false with
						| HObj o -> (try fst (PMap.find f.cf_name o.pindex) with Not_found -> assert false)
						| _ -> assert false
					) in
					op ctx (OGetThis (r,fid));
					op ctx (OJNotNull (r,2));
					op ctx (OClosure (r,alloc_fid ctx c f,0));
					op ctx (OSetThis (fid,r));
				| _ -> ()
			) c.cl_ordered_fields;
		) in
		ignore(make_fun ?gen_content ctx (alloc_fid ctx c f) (match f.cf_expr with Some { eexpr = TFunction f } -> f | _ -> error "Missing function body" f.cf_pos) (Some c) None);
		if f.cf_name = "toString" && not (List.memq f c.cl_overrides) && not (PMap.mem "__string" c.cl_fields) then begin
			let p = f.cf_pos in
			(* function __string() return this.toString().bytes *)
			let ethis = mk (TConst TThis) (TInst (c,List.map snd c.cl_params)) p in
			let tstr = mk (TCall (mk (TField (ethis,FInstance(c,List.map snd c.cl_params,f))) f.cf_type p,[])) ctx.com.basic.tstring p in
			let cstr, cf_bytes = (try (match ctx.com.basic.tstring with TInst(c,_) -> c, PMap.find "bytes" c.cl_fields | _ -> assert false) with Not_found -> assert false) in
			let estr = mk (TReturn (Some (mk (TField (tstr,FInstance (cstr,[],cf_bytes))) cf_bytes.cf_type p))) ctx.com.basic.tvoid p in
			ignore(make_fun ctx (alloc_fun_path ctx c.cl_path "__string") { tf_expr = estr; tf_args = []; tf_type = cf_bytes.cf_type; } (Some c) None)
		end

let generate_enum ctx e =
	()

let generate_type ctx t =
	match t with
	| TClassDecl { cl_interface = true }->
		()
	| TClassDecl c when c.cl_extern ->
		List.iter (fun f ->
			List.iter (fun (name,args,pos) ->
				match name with
				| Meta.Custom ":hlNative" -> generate_static ctx c f
				| _ -> ()
			) f.cf_meta
		) c.cl_ordered_statics
	| TClassDecl c ->
		List.iter (generate_static ctx c) c.cl_ordered_statics;
		(match c.cl_constructor with
		| None -> ()
		| Some f -> generate_member ctx c f);
		List.iter (generate_member ctx c) c.cl_ordered_fields;
	| TTypeDecl _ | TAbstractDecl _ ->
		()
	| TEnumDecl e  ->
		generate_enum ctx e

let generate_static_init ctx =
	let exprs = ref [] in
	let t_void = ctx.com.basic.tvoid in

	let gen_content() =

		op ctx (OCall0 (alloc_tmp ctx HVoid, alloc_fun_path ctx ([],"Type") "init"));

		(* init class values *)
		List.iter (fun t ->
			match t with
			| TClassDecl c when not c.cl_extern && not (is_array_class (s_type_path c.cl_path) && snd c.cl_path <> "ArrayDyn") && c != ctx.core_type && c != ctx.core_enum ->

				let path = if c == ctx.array_impl.abase then [],"Array" else if c == ctx.base_class then [],"Class" else c.cl_path in

				let g, ct = class_global ~resolve:false ctx c in

				let index name =
					match ct with
					| HObj o ->
						fst (try get_index name o with Not_found -> assert false)
					| _ ->
						assert false
				in

				let rc = alloc_tmp ctx ct in
				op ctx (ONew rc);
				op ctx (OSetGlobal (g,rc));

				let rt = alloc_tmp ctx HType in
				let ctype = if c == ctx.array_impl.abase then ctx.array_impl.aall else c in
				op ctx (OType (rt, class_type ctx ctype (List.map snd ctype.cl_params) false));
				op ctx (OSetField (rc,index "__type__",rt));
				op ctx (OSetField (rc,index "__name__",eval_expr ctx { eexpr = TConst (TString (s_type_path path)); epos = c.cl_pos; etype = ctx.com.basic.tstring }));

				let rname = alloc_tmp ctx HBytes in
				op ctx (OString (rname, alloc_string ctx (s_type_path path)));
				op ctx (OCall2 (alloc_tmp ctx HVoid, alloc_fun_path ctx ([],"Type") "register",rname,rc));

				(match c.cl_constructor with
				| None -> ()
				| Some f ->
					(* set __constructor__ *)
					let r = alloc_tmp ctx (match to_type ctx f.cf_type with
						| HFun (args,ret) -> HFun (class_type ctx c (List.map snd c.cl_params) false :: args, ret)
						| _ -> assert false
					) in
					op ctx (OGetFunction (r, alloc_fid ctx c f));
					op ctx (OSetField (rc,index "__constructor__",r)));

				(* register static funs *)

				List.iter (fun f ->
					match f.cf_kind with
					| Method _ when not (is_extern_field f) ->
						let cl = alloc_tmp ctx (to_type ctx f.cf_type) in
						op ctx (OGetFunction (cl, alloc_fid ctx c f));
						op ctx (OSetField (rc,index f.cf_name,cl));
					| _ ->
						()
				) c.cl_ordered_statics;

				(match Codegen.build_metadata ctx.com (TClassDecl c) with
				| None -> ()
				| Some e ->
					let r = eval_to ctx e HDyn in
					op ctx (OSetField (rc,index "__meta__",r)));

			| TEnumDecl e when not e.e_extern ->

				let t = enum_class ctx e in
				let g = alloc_global ctx (match t with HObj o -> o.pname | _ -> assert false) t in

				let index name =
					match t with
					| HObj o ->
						fst (try get_index name o with Not_found -> assert false)
					| _ ->
						assert false
				in
				let r = alloc_tmp ctx t in
				let rt = alloc_tmp ctx HType in
				op ctx (ONew r);

				let max_val = ref (-1) in
				PMap.iter (fun _ c ->
					match follow c.ef_type with
					| TFun _ -> ()
					| _ -> if c.ef_index > !max_val then max_val := c.ef_index;
				) e.e_constrs;

				let avalues = alloc_tmp ctx HArray in
				op ctx (OType (rt, HDyn));
				op ctx (OCall2 (avalues, alloc_std ctx "aalloc" [HType;HI32] HArray, rt, reg_int ctx (!max_val + 1)));

				List.iter (fun n ->
					let f = PMap.find n e.e_constrs in
					match follow f.ef_type with
					| TFun _ -> ()
					| _ ->
						let t = to_type ctx f.ef_type in
						let g = alloc_global ctx (efield_name e f) t in
						let r = alloc_tmp ctx t in
						op ctx (OMakeEnum (r,f.ef_index,[]));
						op ctx (OSetGlobal (g,r));
						let d = alloc_tmp ctx HDyn in
						op ctx (OToDyn (d,r));
						op ctx (OSetArray (avalues, reg_int ctx f.ef_index, d));
				) e.e_names;

				op ctx (OType (rt, (to_type ctx (TEnum (e,List.map snd e.e_params)))));
				op ctx (OCall3 (alloc_tmp ctx HVoid, alloc_fun_path ctx (["hl";"types"],"Enum") "new",r,rt,avalues));

				(match Codegen.build_metadata ctx.com (TEnumDecl e) with
				| None -> ()
				| Some e -> op ctx (OSetField (r,index "__meta__",eval_to ctx e HDyn)));

				op ctx (OSetGlobal (g,r));

			| TAbstractDecl { a_path = [], name; a_pos = pos } ->
				(match name with
				| "Int" | "Float" | "Dynamic" | "Bool" ->
					let is_bool = name = "Bool" in
					let t = class_type ctx (if is_bool then ctx.core_enum else ctx.core_type) [] false in

					let index name =
						match t with
						| HObj o ->
							fst (try get_index name o with Not_found -> assert false)
						| _ ->
							assert false
					in

					let g = alloc_global ctx ("$" ^ name) t in
					let r = alloc_tmp ctx t in
					let rt = alloc_tmp ctx HType in
					op ctx (ONew r);
					op ctx (OType (rt,(match name with "Int" -> HI32 | "Float" -> HF64 | "Dynamic" -> HDyn | "Bool" -> HBool | _ -> assert false)));
					op ctx (OSetField (r,index "__type__",rt));
					op ctx (OSetField (r,index (if is_bool then "__ename__" else "__name__"),make_string ctx name pos));
					op ctx (OSetGlobal (g,r));

					let bytes = alloc_tmp ctx HBytes in
					op ctx (OString (bytes, alloc_string ctx name));
					op ctx (OCall2 (alloc_tmp ctx HVoid, alloc_fun_path ctx ([],"Type") "register",bytes,r));
				| _ ->
					())
			| _ ->
				()

		) ctx.com.types;
	in
	(* init class statics *)
	List.iter (fun t ->
		match t with
		| TClassDecl c when not c.cl_extern ->
			(match c.cl_init with None -> () | Some e -> exprs := e :: !exprs);
			List.iter (fun f ->
				match f.cf_kind, f.cf_expr with
				| Var _, Some e ->
					let p = e.epos in
					let e = mk (TBinop (OpAssign,(mk (TField (mk (TTypeExpr t) t_dynamic p,FStatic (c,f))) f.cf_type p), e)) f.cf_type p in
					exprs := e :: !exprs;
				| _ ->
					()
			) c.cl_ordered_statics;
		| _ -> ()
	) ctx.com.types;
	(* call main() *)
	(match ctx.com.main_class with
	| None -> ()
	| Some m ->
		let t = (try List.find (fun t -> t_path t = m) ctx.com.types with Not_found -> assert false) in
		match t with
		| TClassDecl c ->
			let f = (try PMap.find "main" c.cl_statics with Not_found -> assert false) in
			let p = { pfile = "<startup>"; pmin = 0; pmax = 0; } in
			exprs := mk (TCall (mk (TField (mk (TTypeExpr t) t_dynamic p, FStatic (c,f))) f.cf_type p,[])) t_void p :: !exprs
		| _ ->
			assert false
	);
	let fid = alloc_function_name ctx "<entry>" in
	ignore(make_fun ~gen_content ctx fid { tf_expr = mk (TBlock (List.rev !exprs)) t_void null_pos; tf_args = []; tf_type = t_void } None None);
	fid


(* ------------------------------- CHECK ---------------------------------------------- *)

let check code =
	let ftypes = Array.create (Array.length code.natives + Array.length code.functions) HVoid in
	let is_native_fun = Hashtbl.create 0 in

	let check_fun f =
		let pos = ref 0 in
		let error msg =
			let dfile, dline = f.debug.(!pos) in
			failwith (Printf.sprintf "\n%s:%d: Check failure at %d@%d - %s" code.debugfiles.(dfile) dline f.findex (!pos) msg)
		in
		let targs, tret = (match f.ftype with HFun (args,ret) -> args, ret | _ -> assert false) in
		let rtype i = f.regs.(i) in
		let check t1 t2 =
			if not (safe_cast t1 t2) then error (tstr t1 ^ " should be " ^ tstr t2)
		in
		let reg_inf r =
			"Register " ^ string_of_int r ^ "(" ^ tstr (rtype r) ^ ")"
		in
		let reg r t =
			if not (safe_cast (rtype r) t) then error (reg_inf r ^ " should be " ^ tstr t ^ " and not " ^ tstr (rtype r))
		in
		let numeric r =
			match rtype r with
			| HI8 | HI16 | HI32 | HF32 | HF64 -> ()
			| _ -> error (reg_inf r ^ " should be numeric")
		in
		let int r =
			match rtype r with
			| HI8 | HI16 | HI32 -> ()
			| _ -> error (reg_inf r ^ " should be integral")
		in
		let float r =
			match rtype r with
			| HF32 | HF64 -> ()
			| _ -> error (reg_inf r ^ " should be float")
		in
		let call f args r =
			match ftypes.(f) with
			| HFun (targs, tret) ->
				if List.length args <> List.length targs then error (tstr (HFun (List.map rtype args, rtype r)) ^ " should be " ^ tstr ftypes.(f));
				List.iter2 reg args targs;
				reg r tret
			| _ -> assert false
		in
		let can_jump delta =
			if !pos + 1 + delta < 0 || !pos + 1 + delta >= Array.length f.code then error "Jump outside function bounds";
			if delta < 0 && Array.get f.code (!pos + 1 + delta) <> OLabel 0 then error "Jump back without Label";
		in
		let is_obj r =
			match rtype r with
			| HObj _ -> ()
			| _ -> error (reg_inf r ^ " should be object")
		in
		let is_enum r =
			match rtype r with
			| HEnum _ -> ()
			| _ -> error (reg_inf r ^ " should be enum")
		in
		let is_dyn r =
			if not (is_dynamic (rtype r)) then error (reg_inf r ^ " should be castable to dynamic")
		in
		let tfield o fid proto =
			if fid < 0 then error (reg_inf o ^ " does not have " ^ (if proto then "proto " else "") ^ "field " ^ string_of_int fid);
			match rtype o with
			| HObj p ->
				if proto then ftypes.(p.pvirtuals.(fid)) else (try snd (resolve_field p fid) with Not_found -> error (reg_inf o ^ " does not have field " ^ string_of_int fid))
			| HVirtual v when not proto ->
				let _,_, t = v.vfields.(fid) in
				t
			| _ ->
				is_obj o;
				HVoid
		in
		iteri reg targs;
		Array.iteri (fun i op ->
			pos := i;
			match op with
			| OMov (a,b) ->
				reg b (rtype a)
			| OInt (r,i) ->
				ignore(code.ints.(i));
				int r
			| OFloat (r,i) ->
				if rtype r <> HF32 then reg r HF64;
				if i < 0 || i >= Array.length code.floats then error "float outside range";
			| OBool (r,_) ->
				reg r HBool
			| OString (r,i) | OBytes (r,i) ->
				reg r HBytes;
				if i < 0 || i >= Array.length code.strings then error "string outside range";
			| ONull r ->
				let t = rtype r in
				if not (is_nullable t) then error (tstr t ^ " is not nullable")
			| OAdd (r,a,b) | OSub (r,a,b) | OMul (r,a,b) | OSDiv (r,a,b) | OUDiv (r,a,b) | OSMod (r,a,b) | OUMod(r,a,b) ->
				numeric r;
				reg a (rtype r);
				reg b (rtype r);
			| ONeg (r,a) ->
				numeric r;
				reg a (rtype r);
			| OShl (r,a,b) | OSShr (r,a,b) | OUShr (r,a,b) | OAnd (r,a,b) | OOr (r,a,b) | OXor (r,a,b) ->
				int r;
				reg a (rtype r);
				reg b (rtype r);
			| OIncr r ->
				int r
			| ODecr r ->
				int r
			| ONot (a,b) ->
				reg a HBool;
				reg b HBool;
			| OCall0 (r,f) ->
				call f [] r
			| OCall1 (r, f, a) ->
				call f [a] r
			| OCall2 (r, f, a, b) ->
				call f [a;b] r
			| OCall3 (r, f, a, b, c) ->
				call f [a;b;c] r
			| OCall4 (r, f, a, b, c, d) ->
				call f [a;b;c;d] r
			| OCallN (r,f,rl) ->
				call f rl r
			| OCallThis (r, m, rl) ->
				(match tfield 0 m true with
				| HFun (tobj :: targs, tret) when List.length targs = List.length rl -> reg 0 tobj; List.iter2 reg rl targs; reg r tret
				| t -> check t (HFun (rtype 0 :: List.map rtype rl, rtype r)));
			| OCallMethod (r, m, rl) ->
				(match rl with
				| [] -> assert false
				| obj :: _ ->
					match tfield obj m true with
					| HFun (targs, tret) when List.length targs = List.length rl -> List.iter2 reg rl targs; reg r tret
					| t -> check t (HFun (List.map rtype rl, rtype r)));
			| OCallClosure (r,f,rl) ->
				(match rtype f with
				| HFun (targs,tret) when List.length targs = List.length rl -> List.iter2 reg rl targs; reg r tret
				| HDyn -> List.iter (fun r -> ignore(rtype r)) rl;
				| _ -> reg f (HFun(List.map rtype rl,rtype r)))
			| OGetGlobal (r,g) ->
				if not (safe_cast code.globals.(g) (rtype r)) then reg r code.globals.(g)
			| OSetGlobal (g,r) ->
				reg r code.globals.(g)
			| ORet r ->
				reg r tret
			| OJTrue (r,delta) | OJFalse (r,delta) ->
				reg r HBool;
				can_jump delta
			| OJNull (r,delta) | OJNotNull (r,delta) ->
				ignore(rtype r);
				can_jump delta
			| OJUGte (a,b,delta) | OJULt (a,b,delta) | OJSGte (a,b,delta) | OJSLt (a,b,delta) | OJSGt (a,b,delta) | OJSLte (a,b,delta) ->
				reg a (rtype b);
				can_jump delta
			| OJEq (a,b,delta) | OJNotEq (a,b,delta) ->
				(match rtype a, rtype b with
				| HObj _, HObj _ -> ()
				| ta, tb when safe_cast tb ta -> ()
				| _ -> reg a (rtype b));
				can_jump delta
			| OJAlways d ->
				can_jump d
			| OToDyn (r,a) ->
				(* we can still use OToDyn on nullable if we want to turn them into dynamic *)
				if is_dynamic (rtype a) then reg a HI32; (* don't wrap as dynamic types that can safely be cast to it *)
				if rtype r <> HDyn then reg r (HNull (rtype a))
			| OToSFloat (a,b) | OToUFloat (a,b) ->
				float a;
				(match rtype b with HF32 | HF64 -> () | _ -> int b);
			| OToInt (a,b) ->
				int a;
				(match rtype b with HF32 | HF64 -> () | _ -> int b);
			| OLabel _ ->
				()
			| ONew r ->
				(match rtype r with
				| HDynObj -> ()
				| _ -> is_obj r)
			| OField (r,o,fid) ->
				check (tfield o fid false) (rtype r)
			| OSetField (o,fid,r) ->
				reg r (tfield o fid false)
			| OGetThis (r,fid) ->
				check (tfield 0 fid false) (rtype r)
			| OSetThis(fid,r) ->
				reg r (tfield 0 fid false)
			| OGetFunction (r,f) ->
				reg r ftypes.(f)
			| OMethod (r,o,fid) ->
				(match rtype o with
				| HObj _ ->
					(match tfield o fid true with
					| HFun (t :: tl, tret) ->
						reg o t;
						reg r (HFun (tl,tret));
					| _ ->
						assert false)
				| HVirtual v ->
					let _,_, t = v.vfields.(fid) in
					reg r t;
				| _ ->
					is_obj o)
			| OClosure (r,f,arg) ->
				(match ftypes.(f) with
				| HFun (t :: tl, tret) ->
					reg arg t;
					reg r (HFun (tl,tret));
				| _ -> assert false);
			| OThrow r ->
				reg r HDyn
			| ORethrow r ->
				reg r HDyn
			| OGetArray (v,a,i) ->
				reg a HArray;
				reg i HI32;
				ignore(rtype v);
			| OGetI8 (r,b,p) ->
				reg r HI32;
				reg b HBytes;
				reg p HI32;
			| OGetI32 (r,b,p) ->
				reg r HI32;
				reg b HBytes;
				reg p HI32;
			| OGetF32 (r,b,p) ->
				reg r HF32;
				reg b HBytes;
				reg p HI32;
			| OGetF64 (r,b,p) ->
				reg r HF64;
				reg b HBytes;
				reg p HI32;
			| OSetI8 (r,p,v) ->
				reg r HBytes;
				reg p HI32;
				reg v HI32;
			| OSetI32 (r,p,v) ->
				reg r HBytes;
				reg p HI32;
				reg v HI32;
			| OSetF32 (r,p,v) ->
				reg r HBytes;
				reg p HI32;
				reg v HF32;
			| OSetF64 (r,p,v) ->
				reg r HBytes;
				reg p HI32;
				reg v HF64;
			| OSetArray (a,i,v) ->
				reg a HArray;
				reg i HI32;
				ignore(rtype v);
			| OUnsafeCast (a,b) ->
				is_dyn a;
				is_dyn b;
			| OSafeCast (a,b) ->
				ignore(rtype a);
				ignore(rtype b);
			| OArraySize (r,a) ->
				reg a HArray;
				reg r HI32
			| OError s ->
				ignore(code.strings.(s));
			| OType (r,_) ->
				reg r HType
			| OGetType (r,v) ->
				reg r HType;
				is_dyn v;
			| OGetTID (r,v) ->
				reg r HI32;
				reg v HType;
			| OUnref (v,r) ->
				(match rtype r with
				| HRef t -> check t (rtype v)
				| _ -> reg r (HRef (rtype v)))
			| ORef (r,v)
			| OSetref (r,v) ->
				(match rtype r with HRef t -> reg v t | _ -> reg r (HRef (rtype v)))
			| OToVirtual (r,v) ->
				(match rtype r with
				| HVirtual _ -> ()
				| _ -> reg r (HVirtual {vfields=[||];vindex=PMap.empty;}));
				(match rtype v with
				| HObj _ | HDynObj | HDyn -> ()
				| _ -> reg v HDynObj)
			| OUnVirtual (r,v) ->
				(match rtype v with
				| HVirtual _ -> ()
				| _ -> reg r (HVirtual {vfields=[||];vindex=PMap.empty;}));
				reg r HDyn
			| ODynGet (v,r,f) | ODynSet (r,f,v) ->
				ignore(code.strings.(f));
				ignore(rtype v);
				(match rtype r with
				| HObj _ | HDyn | HDynObj | HVirtual _ -> ()
				| _ -> reg r HDynObj)
			| OMakeEnum (r,index,pl) ->
				(match rtype r with
				| HEnum e ->
					let _,_, fl = e.efields.(index) in
					if Array.length fl <> List.length pl then error ("MakeEnum has " ^ (string_of_int (List.length pl)) ^ " params while " ^ (string_of_int (Array.length fl)) ^ " are required");
					List.iter2 (fun r t -> reg r t) pl (Array.to_list fl)
				| _ ->
					is_enum r)
			| OEnumAlloc (r,index) ->
				(match rtype r with
				| HEnum e ->
					ignore(e.efields.(index))
				| _ ->
					is_enum r)
			| OEnumIndex (r,v) ->
				if rtype v <> HDyn then is_enum v;
				reg r HI32;
			| OEnumField (r,e,f,i) ->
				(match rtype e with
				| HEnum e ->
					let _, _, tl = e.efields.(f) in
					check tl.(i) (rtype r)
				| _ -> is_enum e)
			| OSetEnumField (e,i,r) ->
				(match rtype e with
				| HEnum e ->
					let _, _, tl = e.efields.(0) in
					check (rtype r) tl.(i)
				| _ -> is_enum e)
			| OSwitch (r,idx) ->
				reg r HI32;
				Array.iter can_jump idx
			| ONullCheck r ->
				ignore(rtype r)
			| OTrap (r, idx) ->
				reg r HDyn;
				can_jump idx
			| OEndTrap _ ->
				()
			| ODump r ->
				ignore(rtype r);
		) f.code
		(* TODO : check that all path correctly initialize NULL values and reach a return *)
	in
	Array.iter (fun fd ->
		if fd.findex >= Array.length ftypes then failwith ("Invalid function index " ^ string_of_int fd.findex);
		if ftypes.(fd.findex) <> HVoid then failwith ("Duplicate function bind " ^ string_of_int fd.findex);
		ftypes.(fd.findex) <- fd.ftype;
	) code.functions;
	Array.iter (fun (_,_,t,idx) ->
		if idx >= Array.length ftypes then failwith ("Invalid native function index " ^ string_of_int idx);
		if ftypes.(idx) <> HVoid then failwith ("Duplicate native function bind " ^ string_of_int idx);
		Hashtbl.add is_native_fun idx true;
		ftypes.(idx) <- t
	) code.natives;
	(* TODO : check that no object type has a virtual native in his proto *)
	Array.iter check_fun code.functions

(* ------------------------------- INTERP --------------------------------------------- *)

type value =
	| VNull
	| VInt of int32
	| VFloat of float
	| VBool of bool
	| VDyn of value * ttype
	| VObj of vobject
	| VClosure of vfunction * value option
	| VBytes of string
	| VArray of value array * ttype
	| VUndef
	| VType of ttype
	| VRef of value array * int * ttype
	| VVirtual of vvirtual
	| VDynObj of vdynobj
	| VEnum of int * value array
	| VAbstract of vabstract
	| VVarArgs of vfunction * value option

and vabstract =
	| AHashBytes of (string, value) Hashtbl.t
	| AHashInt of (int32, value) Hashtbl.t
	| AHashObject of (value * value) list ref
	| AReg of regexp

and vfunction =
	| FFun of fundecl
	| FNativeFun of string * (value list -> value) * ttype

and vobject = {
	oproto : vproto;
	ofields : value array;
}

and vproto = {
	pclass : class_proto;
	pmethods : vfunction array;
}

and vvirtual = {
	vtype : virtual_proto;
	mutable vindexes : vfield array;
	mutable vtable : value array;
	vvalue : value;
}

and vdynobj = {
	dfields : (string, int) Hashtbl.t;
	mutable dtypes : ttype array;
	mutable dvalues : value array;
	mutable dvirtuals : vvirtual list;
}

and vfield =
	| VFNone
	| VFIndex of int

and regexp = {
	r : Str.regexp;
	mutable r_string : string;
	mutable r_groups : (int * int) option array;
}

exception Return of value

let default t =
	match t with
	| HI8 | HI16 | HI32 -> VInt Int32.zero
	| HF32 | HF64 -> VFloat 0.
	| HBool -> VBool false
	| _ -> if is_nullable t then VNull else VUndef

let get_type = function
	| VDyn (_,t) -> Some t
	| VObj o -> Some (HObj o.oproto.pclass)
	| VDynObj _ -> Some HDynObj
	| VVirtual v -> Some (HVirtual v.vtype)
	| VArray _ -> Some HArray
	| VClosure (f,None) -> Some (match f with FFun f -> f.ftype | FNativeFun (_,_,t) -> t)
	| VClosure (f,Some _) -> Some (match f with FFun { ftype = HFun(_::args,ret) } | FNativeFun (_,_,HFun(_::args,ret)) -> HFun (args,ret) | _ -> assert false)
	| VVarArgs _ -> Some (HFun ([],HDyn))
	| _ -> None

let v_dynamic = function
	| VNull	| VDyn _ | VObj _ | VClosure _ | VArray _ | VVirtual _ | VDynObj _ | VVarArgs _ -> true
	| _ -> false

let rec is_compatible v t =
	match v, t with
	| VInt _, (HI8 | HI16 | HI32) -> true
	| VFloat _, (HF32 | HF64) -> true
	| VBool _, HBool -> true
	| VNull, t -> is_nullable t
	| VObj o, HObj _ -> safe_cast (HObj o.oproto.pclass) t
	| VClosure _, HFun _ -> safe_cast (match get_type v with None -> assert false | Some t -> t) t
	| VBytes _, HBytes -> true
	| VDyn (_,t1), HNull t2 -> tsame t1 t2
	| v, HNull t -> is_compatible v t
	| v, HDyn -> v_dynamic v
	| VUndef, HVoid -> true
	| VType _, HType -> true
	| VArray _, HArray -> true
	| VDynObj _, HDynObj -> true
	| VVirtual v, HVirtual _ -> safe_cast (HVirtual v.vtype) t
	| VRef (_,_,t1), HRef t2 -> tsame t1 t2
	| VAbstract _, HAbstract _ -> true
	| VEnum _, HEnum _ -> true
	| _ -> false

exception Runtime_error of string
exception InterpThrow of value

type cast =
	| CNo
	| CDyn of ttype
	| CUnDyn of ttype
	| CCast of ttype * ttype

let interp code =

	let globals = Array.map default code.globals in
	let functions = Array.create (Array.length code.functions + Array.length code.natives) (FNativeFun ("",(fun _ -> assert false),HDyn)) in
	let cached_protos = Hashtbl.create 0 in
	let func f = Array.unsafe_get functions f in

	let stack = ref [] in
	let exc_stack = ref [] in

	let rec get_proto p =
		try
			Hashtbl.find cached_protos p.pname
		with Not_found ->
			let fields = (match p.psuper with None -> [||] | Some p -> snd(get_proto p)) in
			let meths = Array.map (fun f -> functions.(f)) p.pvirtuals in
			let fields = Array.append fields (Array.map (fun (_,_,t) -> t) p.pfields) in
			let proto = ({ pclass = p; pmethods = meths },fields) in
			Hashtbl.replace cached_protos p.pname proto;
			proto
	in

	let utf16_iter f s =
		let get v = int_of_char s.[v] in
		let rec loop p =
			if p = String.length s then () else
			let c = (get p) lor ((get (p+1)) lsl 8) in
			if c >= 0xD800 && c <= 0xDFFF then begin
				let c = c - 0xD800 in
				let c2 = ((get (p+2)) lor ((get(p+3)) lsl 8)) - 0xDC00 in
				f ((c2 lor (c lsl 10)) + 0x10000);
				loop (p + 4);
			end else begin
				f c;
				loop (p + 2);
			end;
		in
		loop 0
	in

	let utf16_eof s =
		let get v = int_of_char s.[v] in
		let rec loop p =
			let c = (get p) lor ((get (p+1)) lsl 8) in
			if c = 0 then String.sub s 0 p else loop (p + 2);
		in
		loop 0
	in

	let utf16_char buf c =
		utf16_add buf (int_of_char c)
	in

	let caml_to_hl str = utf8_to_utf16 str in

	let hl_to_caml str =
		let b = UTF8.Buf.create (String.length str / 2) in
		utf16_iter (fun c -> UTF8.Buf.add_char b (UChar.chr c)) (utf16_eof str);
		UTF8.Buf.contents b
	in

	let hl_to_caml_sub str pos len =
		hl_to_caml (String.sub str pos len ^ "\x00\x00")
	in

	let error msg = raise (Runtime_error msg) in
	let throw v = exc_stack := []; raise (InterpThrow v) in
	let throw_msg msg = throw (VDyn (VBytes (caml_to_hl msg),HBytes)) in

	let hash_cache = Hashtbl.create 0 in

	let hash str =
		let h = hash str in
		if not (Hashtbl.mem hash_cache h) then Hashtbl.add hash_cache h (String.sub str 0 (try String.index str '\000' with _ -> String.length str));
		h
	in

	let null_access() =
		error "Null value bypass null pointer check"
	in

	let make_dyn v t =
		if v = VNull || is_dynamic t then
			v
		else
			VDyn (v,t)
	in

	let rec get_method p name =
		let m = ref None in
		Array.iter (fun p -> if p.fname = name then m := Some p.fmethod) p.pproto;
		match !m , p.psuper with
		| Some i, _ -> Some i
		| None, Some s -> get_method s name
		| None, None -> None
	in

	let invalid_comparison = 255 in

	let rec vstr_d v =
		match v with
		| VNull -> "null"
		| VInt i -> Int32.to_string i ^ "i"
		| VFloat f -> float_repres f ^ "f"
		| VBool b -> if b then "true" else "false"
		| VDyn (v,t) -> "dyn(" ^ vstr_d v ^ ":" ^ tstr t ^ ")"
		| VObj o ->
			let p = "#" ^ o.oproto.pclass.pname in
			(match get_method o.oproto.pclass "__string" with
			| None -> p
			| Some f -> p ^ ":" ^ vstr_d (fcall (func f) [v]))
		| VBytes b -> "bytes(" ^ String.escaped b ^ ")"
		| VClosure (f,o) ->
			(match o with
			| None -> fstr f
			| Some v -> fstr f ^ "[" ^ vstr_d v ^ "]")
		| VArray (a,t) -> "array<" ^ tstr t ^ ">(" ^ String.concat "," (Array.to_list (Array.map vstr_d a)) ^ ")"
		| VUndef -> "undef"
		| VType t -> "type(" ^ tstr t ^ ")"
		| VRef (regs,i,_) -> "ref(" ^ vstr_d regs.(i) ^ ")"
		| VVirtual v -> "virtual(" ^ vstr_d v.vvalue ^ ")"
		| VDynObj d -> "dynobj(" ^ String.concat "," (Hashtbl.fold (fun f i acc -> (f^":"^vstr_d d.dvalues.(i)) :: acc) d.dfields []) ^ ")"
		| VEnum (i,vals) -> "enum#" ^ string_of_int i  ^ "(" ^ String.concat "," (Array.to_list (Array.map vstr_d vals)) ^ ")"
		| VAbstract _ -> "abstract"
		| VVarArgs _ -> "varargs"

	and vstr v t =
		match v with
		| VNull -> "null"
		| VInt i -> Int32.to_string i
		| VFloat f ->
			let s = float_repres f in
			let len = String.length s in
			if String.unsafe_get s (len - 1) = '.' then String.sub s 0 (len - 1) else s
		| VBool b -> if b then "true" else "false"
		| VDyn (v,t) ->
			vstr v t
		| VObj o ->
			(match get_method o.oproto.pclass "__string" with
			| None -> "#" ^ o.oproto.pclass.pname
			| Some f -> vstr (fcall (func f) [v]) HBytes)
		| VBytes b -> (try hl_to_caml b with _ -> "?" ^ String.escaped b)
		| VClosure (f,_) -> fstr f
		| VArray (a,t) -> "[" ^ String.concat ", " (Array.to_list (Array.map (fun v -> vstr v t) a)) ^ "]"
		| VUndef -> "undef"
		| VType t -> tstr t
		| VRef (regs,i,t) -> "*" ^ (vstr regs.(i) t)
		| VVirtual v -> vstr v.vvalue HDyn
		| VDynObj d ->
			(try
				let fid = Hashtbl.find d.dfields "__string" in
				vstr (dyn_call d.dvalues.(fid) [] HBytes) HBytes
			with Not_found ->
				"{" ^ String.concat ", " (Hashtbl.fold (fun f i acc -> (f^":"^vstr d.dvalues.(i) d.dtypes.(i)) :: acc) d.dfields []) ^ "}")
		| VAbstract _ -> "abstract"
		| VEnum (i,vals) ->
			(match t with
			| HEnum e ->
				let n, _, pl = e.efields.(i) in
				if Array.length pl = 0 then
					n
				else
					n ^ "(" ^ String.concat "," (List.map2 vstr (Array.to_list vals) (Array.to_list pl)) ^ ")"
			| _ ->
				assert false)
		| VVarArgs _ -> "varargs"

	and fstr = function
		| FFun f -> "function@" ^ string_of_int f.findex
		| FNativeFun (s,_,_) -> "native[" ^ s ^ "]"

	and fcall f args =
		match f with
		| FFun f -> call f args
		| FNativeFun (_,f,_) ->
			try
				f args
			with InterpThrow v ->
				raise (InterpThrow v)
			| Failure msg ->
				throw_msg msg
			| e ->
				throw_msg (Printexc.to_string e)

	and rebuild_virtuals d =
		let old = d.dvirtuals in
		d.dvirtuals <- [];
		List.iter (fun v ->
			let v2 = (match to_virtual (VDynObj d) v.vtype with VVirtual v -> v | _ -> assert false) in
			v.vindexes <- v2.vindexes;
			v.vtable <- d.dvalues;
		) old;
		d.dvirtuals <- old;

	and dyn_set_field obj field v vt =
		let v, vt = (match vt with
			| HDyn ->
				(match get_type v with
				| None -> if v = VNull then VNull, HDyn else assert false
				| Some t -> (match v with VDyn (v,_) -> v | _ -> v), t)
			| t -> v, t
		) in
		match obj with
		| VDynObj d ->
			(try
				let idx = Hashtbl.find d.dfields field in
				d.dvalues.(idx) <- v;
				if not (tsame d.dtypes.(idx) vt) then begin
					d.dtypes.(idx) <- vt;
					rebuild_virtuals d;
				end;
			with Not_found ->
				let idx = Array.length d.dvalues in
				Hashtbl.add d.dfields field idx;
				let vals2 = Array.make (idx + 1) VNull in
				let types2 = Array.make (idx + 1) HVoid in
				Array.blit d.dvalues 0 vals2 0 idx;
				Array.blit d.dtypes 0 types2 0 idx;
				vals2.(idx) <- v;
				types2.(idx) <- vt;
				d.dvalues <- vals2;
				d.dtypes <- types2;
				rebuild_virtuals d;
			)
		| VObj o ->
			(try
				let idx, t = get_index field o.oproto.pclass in
				if idx < 0 then raise Not_found;
				o.ofields.(idx) <- dyn_cast v vt t
			with Not_found ->
				throw_msg (o.oproto.pclass.pname ^ " has no field " ^ field))
		| VVirtual vp ->
			dyn_set_field vp.vvalue field v vt
		| VNull ->
			null_access()
		| _ ->
			throw_msg "Invalid object access"

	and dyn_get_field obj field rt =
		let get_with v t = dyn_cast v t rt in
		match obj with
		| VDynObj d ->
			(try
				let idx = Hashtbl.find d.dfields field in
				get_with d.dvalues.(idx) d.dtypes.(idx)
			with Not_found ->
				default rt)
		| VObj o ->
			let default rt =
				match get_method o.oproto.pclass "__get_field" with
				| None -> default rt
				| Some f ->
					get_with (fcall (func f) [obj; VInt (hash field)]) HDyn
			in
			let rec loop p =
				try
					let fid = PMap.find field p.pfunctions in
					(match functions.(fid) with
					| FFun fd as f -> get_with (VClosure (f,Some obj)) (match fd.ftype with HFun (_::args,t) -> HFun(args,t) | _ -> assert false)
					| FNativeFun _ -> assert false)
				with Not_found ->
					match p.psuper with
					| None -> default rt
					| Some p -> loop p
			in
			(try
				let idx, t = get_index field o.oproto.pclass in
				if idx < 0 then raise Not_found;
				get_with o.ofields.(idx) t
			with Not_found ->
				loop o.oproto.pclass)
		| VVirtual vp ->
			dyn_get_field vp.vvalue field rt
		| VNull ->
			null_access()
		| _ ->
			throw_msg "Invalid object access"

	and dyn_cast v t rt =
		let invalid() =
			error ("Can't cast " ^ vstr_d v ^ ":"  ^ tstr t ^ " to " ^ tstr rt)
		in
		let default() =
			let v = default rt in
			if v = VUndef then invalid();
			v
		in
		if safe_cast t rt then
			v
		else if v = VNull then
			default()
		else match t, rt with
		| (HI8|HI16|HI32), (HF32|HF64) ->
			(match v with VInt i -> VFloat (Int32.to_float i) | _ -> assert false)
		| (HF32|HF64), (HI8|HI16|HI32) ->
			(match v with VFloat f -> VInt (Int32.of_float f) | _ -> assert false)
		| (HI8|HI16|HI32|HF32|HF64), HNull ((HI8|HI16|HI32|HF32|HF64) as rt) ->
			let v = dyn_cast v t rt in
			VDyn (v,rt)
		| HBool, HNull HBool ->
			VDyn (v,HBool)
		| _, HDyn ->
			make_dyn v t
		| HFun (args1,t1), HFun (args2,t2) when List.length args1 = List.length args2 ->
			(match v with
			| VClosure (fn,farg) ->
				let get_conv t1 t2 =
					if safe_cast t1 t2 || (t2 = HDyn && is_dynamic t1) then CNo
					else if t2 = HDyn then CDyn t1
					else if t1 = HDyn then CUnDyn t2
					else CCast (t1,t2)
				in
				let conv = List.map2 get_conv args2 args1 in
				let rconv = get_conv t1 t2 in
				let convert v c =
					match c with
					| CNo -> v
					| CDyn t -> make_dyn v t
					| CUnDyn t -> dyn_cast v HDyn t
					| CCast (t1,t2) -> dyn_cast v t1 t2
				in
				VClosure (FNativeFun ("~convert",(fun args ->
					let args = List.map2 convert args conv in
					let ret = fcall fn (match farg with None -> args | Some a -> a :: args) in
					convert ret rconv
				),rt),None)
			| _ ->
				assert false)
		| HDyn, HFun (targs,tret) when (match v with VVarArgs _ -> true | _ -> false) ->
			VClosure (FNativeFun ("~varargs",(fun args ->
				dyn_call v (List.map2 (fun v t -> (v,t)) args targs) tret
			),rt),None)
		| HDyn, _ ->
			(match get_type v with
			| None -> assert false
			| Some t -> dyn_cast (match v with VDyn (v,_) -> v | _ -> v) t rt)
		| HNull t, _ ->
			(match v with
			| VDyn (v,t) -> dyn_cast v t rt
			| _ -> assert false)
		| HObj _, HObj b when safe_cast rt t && (match get_type v with Some t -> safe_cast t rt | None -> assert false) ->
			(* downcast *)
			v
		| (HObj _ | HDynObj | HVirtual _), HVirtual vp ->
			to_virtual v vp
		| HObj p, _ ->
			(match get_method p "__cast" with
			| None -> invalid()
			| Some f ->
				if v = VNull then VNull else
				let ret = fcall (func f) [v;VType rt] in
				if ret <> VNull && (match get_type ret with None -> assert false | Some vt -> safe_cast vt rt) then ret else invalid())
		| _ ->
			invalid()

	and dyn_call v args tret =
		match v with
		| VClosure (f,a) ->
			let ft = (match f with FFun f -> f.ftype | FNativeFun (_,_,t) -> t) in
			let fargs, fret = (match ft with HFun (a,t) -> a, t | _ -> assert false) in
			let full_args = args and full_fargs = (match a with None -> fargs | Some _ -> List.tl fargs) in
			let rec loop args fargs =
				match args, fargs with
				| [], [] -> []
				| _, [] -> throw_msg (Printf.sprintf "Too many arguments (%s) != (%s)" (String.concat "," (List.map (fun (v,_) -> vstr_d v) full_args)) (String.concat "," (List.map tstr full_fargs)))
				| (v,t) :: args, ft :: fargs -> dyn_cast v t ft :: loop args fargs
				| [], _ :: fargs -> default ft :: loop args fargs
			in
			let vargs = loop args full_fargs in
			let v = fcall f (match a with None -> vargs | Some a -> a :: vargs) in
			dyn_cast v fret tret
		| VNull ->
			null_access()
		| VVarArgs (f,a) ->
			let arr = VArray (Array.of_list (List.map (fun (v,t) -> make_dyn v t) args),HDyn) in
			dyn_call (VClosure (f,a)) [arr,HArray] tret
		| _ ->
			throw_msg (vstr_d v ^ " cannot be called")

	and dyn_compare a at b bt =
		if a == b && (match at with HF32 | HF64 -> false | _ -> true) then 0 else
		let fcompare (a:float) (b:float) = if a = b then 0 else if a > b then 1 else if a < b then -1 else invalid_comparison in
		match a, b with
		| VInt a, VInt b -> Int32.compare a b
		| VInt a, VFloat b -> fcompare (Int32.to_float a) b
		| VFloat a, VInt b -> fcompare a (Int32.to_float b)
		| VFloat a, VFloat b -> fcompare a b
		| VBool a, VBool b -> compare a b
		| VNull, VNull -> 0
		| VType t1, VType t2 -> if tsame t1 t2 then 0 else 1
		| VNull, _ -> 1
		| _, VNull -> -1
		| VObj oa, VObj ob ->
			if oa == ob then 0 else
			(match get_method oa.oproto.pclass "__compare" with
			| None -> invalid_comparison
			| Some f -> (match fcall (func f) [a;b] with VInt i -> Int32.to_int i | _ -> assert false));
		| VDyn (v,t), _ ->
			dyn_compare v t b bt
		| _, VDyn (v,t) ->
			dyn_compare a at v t
		| _ ->
			invalid_comparison

	and alloc_obj t =
		match t with
		| HDynObj -> VDynObj { dfields = Hashtbl.create 0; dvalues = [||]; dtypes = [||]; dvirtuals = []; }
		| HObj p ->
			let p, fields = get_proto p in
			VObj { oproto = p; ofields = Array.map default fields }
		| _ -> assert false

	and set_i32 b p v =
		String.set b p (char_of_int ((Int32.to_int v) land 0xFF));
		String.set b (p+1) (char_of_int ((Int32.to_int (Int32.shift_right_logical v 8)) land 0xFF));
		String.set b (p+2) (char_of_int ((Int32.to_int (Int32.shift_right_logical v 16)) land 0xFF));
		String.set b (p+3) (char_of_int (Int32.to_int (Int32.shift_right_logical v 24)));

	and get_i32 b p =
		let i = int_of_char (String.get b p) in
		let j = int_of_char (String.get b (p + 1)) in
		let k = int_of_char (String.get b (p + 2)) in
		let l = int_of_char (String.get b (p + 3)) in
		Int32.logor (Int32.of_int (i lor (j lsl 8) lor (k lsl 16))) (Int32.shift_left (Int32.of_int l) 24);

	and to_virtual v vp =
		match v with
		| VNull ->
			VNull
		| VObj o ->
			let indexes = Array.mapi (fun i (n,_,t) ->
				try
					let idx, ft = get_index n o.oproto.pclass in
					if idx < 0 || not (tsame t ft) then raise Not_found;
					VFIndex idx
				with Not_found ->
					VFNone (* most likely a method *)
			) vp.vfields in
			let v = {
				vtype = vp;
				vindexes = indexes;
				vtable = o.ofields;
				vvalue = v;
			} in
			VVirtual v
		| VDynObj d ->
			(try
				VVirtual (List.find (fun v -> v.vtype == vp) d.dvirtuals)
			with Not_found ->
				let indexes = Array.mapi (fun i (n,_,t) ->
					try
						let idx = Hashtbl.find d.dfields n in
						if not (tsame t d.dtypes.(idx)) then raise Not_found;
						VFIndex idx
					with Not_found ->
						VFNone
				) vp.vfields in
				let v = {
					vtype = vp;
					vindexes = indexes;
					vtable = d.dvalues;
					vvalue = v;
				} in
				d.dvirtuals <- v :: d.dvirtuals;
				VVirtual v
			)
		| VVirtual v ->
			to_virtual v.vvalue vp
		| _ ->
			error ("Invalid ToVirtual " ^ vstr_d v ^ " : " ^ tstr (HVirtual vp))

	and call f args =
		let regs = Array.create (Array.length f.regs) VUndef in
		let pos = ref 1 in

		stack := (f,pos) :: !stack;
		let fret = (match f.ftype with
			| HFun (fargs,fret) ->
				if List.length fargs <> List.length args then error (Printf.sprintf "Invalid args: (%s) should be (%s)" (String.concat "," (List.map vstr_d args)) (String.concat "," (List.map tstr fargs)));
				fret
			| _ -> assert false
		) in
		let rtype i = f.regs.(i) in
		let check v t id =
			if not (is_compatible v t) then error (Printf.sprintf "Can't set %s(%s) with %s" (id()) (tstr t) (vstr_d v));
		in
		let check_obj v o fid =
			match o with
			| VObj o ->
				let _, fields = get_proto o.oproto.pclass in
				check v fields.(fid) (fun() -> "obj field")
			| VVirtual vp ->
				let _,_, t = vp.vtype.vfields.(fid) in
				check v t (fun() -> "virtual field")
			| _ ->
				()
		in
		let set r v =
			(*if f.findex = 0 then Printf.eprintf "%d@%d set %d = %s\n" f.findex (!pos - 1) r (vstr_d v);*)
			check v (rtype r) (fun() -> "register " ^ string_of_int r);
			Array.unsafe_set regs r v
		in
		iteri set args;
		let get r = Array.unsafe_get regs r in
		let global g = Array.unsafe_get globals g in
		let traps = ref [] in
		let numop iop fop a b =
			match rtype a with
			(* todo : sign-extend and mask after result for HI8/16 *)
			| HI8 | HI16 | HI32 ->
				(match regs.(a), regs.(b) with
				| VInt a, VInt b -> VInt (iop a b)
				| _ -> assert false)
			| HF32 | HF64 ->
				(match regs.(a), regs.(b) with
				| VFloat a, VFloat b -> VFloat (fop a b)
				| _ -> assert false)
			| _ ->
				assert false
		in
		let iop f a b =
			match rtype a with
			(* todo : sign-extend and mask after result for HI8/16 *)
			| HI8 | HI16 | HI32 ->
				(match regs.(a), regs.(b) with
				| VInt a, VInt b -> VInt (f a b)
				| _ -> assert false)
			| _ ->
				assert false
		in
		let iunop iop r =
			match rtype r with
			| HI8 | HI16 | HI32 ->
				(match regs.(r) with
				| VInt a -> VInt (iop a)
				| _ -> assert false)
			| _ ->
				assert false
		in
		let ucompare a b =
			match a, b with
			| VInt a, VInt b ->
				let d = Int32.sub (Int32.shift_right_logical a 16) (Int32.shift_right_logical b 16) in
				Int32.to_int (if d = 0l then Int32.sub (Int32.logand a 0xFFFFl) (Int32.logand b 0xFFFFl) else d)
			| _ -> assert false
		in
		let vcompare ra rb op =
			let a = get ra in
			let b = get rb in
			let t = rtype ra in
			let r = dyn_compare a t b t in
			if r = invalid_comparison then false else op r 0
		in
		let ufloat v =
			if v < 0l then Int32.to_float v +. 4294967296. else Int32.to_float v
		in
		let rec loop() =
			let op = f.code.(!pos) in
			incr pos;
			(match op with
			| OMov (a,b) -> set a (get b)
			| OInt (r,i) -> set r (VInt code.ints.(i))
			| OFloat (r,i) -> set r (VFloat (Array.unsafe_get code.floats i))
			| OString (r,s) -> set r (VBytes (caml_to_hl code.strings.(s)))
			| OBytes (r,s) -> set r (VBytes (code.strings.(s) ^ "\x00"))
			| OBool (r,b) -> set r (VBool b)
			| ONull r -> set r VNull
			| OAdd (r,a,b) -> set r (numop Int32.add ( +. ) a b)
			| OSub (r,a,b) -> set r (numop Int32.sub ( -. ) a b)
			| OMul (r,a,b) -> set r (numop Int32.mul ( *. ) a b)
			| OSDiv (r,a,b) -> set r (numop (fun a b -> if b = 0l then 0l else Int32.div a b) ( /. ) a b)
			| OUDiv (r,a,b) -> set r (iop (fun a b -> if b = 0l then 0l else Int32.of_float ((ufloat a) /. (ufloat b))) a b)
			| OSMod (r,a,b) -> set r (numop (fun a b -> if b = 0l then 0l else Int32.rem a b) mod_float a b)
			| OUMod (r,a,b) -> set r (iop (fun a b -> if b = 0l then 0l else Int32.of_float (mod_float (ufloat a) (ufloat b))) a b)
			| OShl (r,a,b) -> set r (iop (fun a b -> Int32.shift_left a (Int32.to_int b)) a b)
			| OSShr (r,a,b) -> set r (iop (fun a b -> Int32.shift_right a (Int32.to_int b)) a b)
			| OUShr (r,a,b) -> set r (iop (fun a b -> Int32.shift_right_logical a (Int32.to_int b)) a b)
			| OAnd (r,a,b) -> set r (iop Int32.logand a b)
			| OOr (r,a,b) -> set r (iop Int32.logor a b)
			| OXor (r,a,b) -> set r (iop Int32.logxor a b)
			| ONeg (r,v) -> set r (match get v with VInt v -> VInt (Int32.neg v) | VFloat f -> VFloat (-. f) | _ -> assert false)
			| ONot (r,v) -> set r (match get v with VBool b -> VBool (not b) | _ -> assert false)
			| OIncr r -> set r (iunop (fun i -> Int32.add i 1l) r)
			| ODecr r -> set r (iunop (fun i -> Int32.sub i 1l) r)
			| OCall0 (r,f) -> set r (fcall (func f) [])
			| OCall1 (r,f,r1) -> set r (fcall (func f) [get r1])
			| OCall2 (r,f,r1,r2) -> set r (fcall (func f) [get r1;get r2])
			| OCall3 (r,f,r1,r2,r3) -> set r (fcall (func f) [get r1;get r2;get r3])
			| OCall4 (r,f,r1,r2,r3,r4) -> set r (fcall (func f) [get r1;get r2;get r3;get r4])
			| OCallN (r,f,rl) -> set r (fcall (func f) (List.map get rl))
			| OGetGlobal (r,g) -> set r (global g)
			| OSetGlobal (g,r) ->
				let v = get r in
				check v code.globals.(g) (fun() -> "global " ^ string_of_int g);
				Array.unsafe_set globals g v
			| OJTrue (r,i) -> if get r = VBool true then pos := !pos + i
			| OJFalse (r,i) -> if get r = VBool false then pos := !pos + i
			| ORet r -> raise (Return regs.(r))
			| OJNull (r,i) -> if get r == VNull then pos := !pos + i
			| OJNotNull (r,i) -> if get r != VNull then pos := !pos + i
			| OJSLt (a,b,i) -> if vcompare a b (<) then pos := !pos + i
			| OJSGte (a,b,i) -> if vcompare a b (>=) then pos := !pos + i
			| OJSGt (a,b,i) -> if vcompare a b (>) then pos := !pos + i
			| OJSLte (a,b,i) -> if vcompare a b (<=) then pos := !pos + i
			| OJULt (a,b,i) -> if ucompare (get a) (get b) < 0 then pos := !pos + i
			| OJUGte (a,b,i) -> if ucompare (get a) (get b) >= 0 then pos := !pos + i
			| OJEq (a,b,i) -> if vcompare a b (=) then pos := !pos + i
			| OJNotEq (a,b,i) -> if not (vcompare a b (=)) then pos := !pos + i
			| OJAlways i -> pos := !pos + i
			| OToDyn (r,a) -> set r (make_dyn (get a) f.regs.(a))
			| OToSFloat (r,a) -> set r (match get a with VInt v -> VFloat (Int32.to_float v) | VFloat _ as v -> v | _ -> assert false)
			| OToUFloat (r,a) -> set r (match get a with VInt v -> VFloat (ufloat v) | VFloat _ as v -> v | _ -> assert false)
			| OToInt (r,a) -> set r (match get a with VFloat v -> VInt (Int32.of_float v) | VInt _ as v -> v | _ -> assert false)
			| OLabel _ -> ()
			| ONew r ->
				set r (alloc_obj (rtype r))
			| OField (r,o,fid) ->
				set r (match get o with
					| VObj v -> v.ofields.(fid)
					| VVirtual v as obj ->
						(match v.vindexes.(fid) with
						| VFNone -> dyn_get_field obj (let n,_,_ = v.vtype.vfields.(fid) in n) (rtype r)
						| VFIndex i -> v.vtable.(i))
					| VNull -> null_access()
					| _ -> assert false)
			| OSetField (o,fid,r) ->
				let rv = get r in
				let o = get o in
				(match o with
				| VObj v ->
					check_obj rv o fid;
					v.ofields.(fid) <- rv
				| VVirtual v ->
					(match v.vindexes.(fid) with
					| VFNone ->
						dyn_set_field o (let n,_,_ = v.vtype.vfields.(fid) in n) rv (rtype r)
					| VFIndex i ->
						check_obj rv o fid;
						v.vtable.(i) <- rv)
				| VNull -> null_access()
				| _ -> assert false)
			| OGetThis (r, fid) ->
				set r (match get 0 with VObj v -> v.ofields.(fid) | _ -> assert false)
			| OSetThis (fid, r) ->
				(match get 0 with
				| VObj v as o ->
					let rv = get r in
					check_obj rv o fid;
					v.ofields.(fid) <- rv
				| _ -> assert false)
			| OCallMethod (r,m,rl) ->
				(match get (List.hd rl) with
				| VObj v -> set r (fcall v.oproto.pmethods.(m) (List.map get rl))
				| VNull -> null_access()
				| _ -> assert false)
			| OCallThis (r,m,rl) ->
				(match get 0 with
				| VObj v as o -> set r (fcall v.oproto.pmethods.(m) (o :: List.map get rl))
				| _ -> assert false)
			| OCallClosure (r,v,rl) ->
				if rtype v = HDyn then
					set r (dyn_call (get v) (List.map (fun r -> get r, rtype r) rl) (rtype r))
				else (match get v with
				| VClosure (f,None) -> set r (fcall f (List.map get rl))
				| VClosure (f,Some arg) -> set r (fcall f (arg :: List.map get rl))
				| VNull -> null_access()
				| _ -> assert false)
			| OGetFunction (r, fid) ->
				let f = functions.(fid) in
				set r (VClosure (f,None))
			| OClosure (r, fid, v) ->
				let f = functions.(fid) in
				set r (VClosure (f,Some (get v)))
			| OMethod (r, o, m) ->
				let m = (match get o with
				| VObj v as obj -> VClosure (v.oproto.pmethods.(m), Some obj)
				| VNull -> null_access()
				| VVirtual v ->
					let name, _, _ = v.vtype.vfields.(m) in
					(match v.vvalue with
					| VObj o as obj ->
						(try
							let m = PMap.find name o.oproto.pclass.pfunctions in
							VClosure (functions.(m), Some obj)
						with Not_found ->
							VNull)
					| _ -> assert false)
				| _ -> assert false
				) in
				set r (if m = VNull then m else dyn_cast m (match get_type m with None -> assert false | Some v -> v) (rtype r))
			| OThrow r ->
				throw (get r)
			| ORethrow r ->
				stack := List.rev !exc_stack @ !stack;
				throw (get r)
			| OGetI8 (r,b,p) ->
				(match get b, get p with
				| VBytes b, VInt p -> set r (VInt (Int32.of_int (int_of_char (String.get b (Int32.to_int p)))))
				| _ -> assert false)
			| OGetI32 (r,b,p) ->
				(match get b, get p with
				| VBytes b, VInt p -> set r (VInt (get_i32 b (Int32.to_int p)))
				| _ -> assert false)
			| OGetF32 (r,b,p) ->
				(match get b, get p with
				| VBytes b, VInt p -> set r (VFloat (Int32.float_of_bits (get_i32 b (Int32.to_int p))))
				| _ -> assert false)
			| OGetF64 (r,b,p) ->
				(match get b, get p with
				| VBytes b, VInt p ->
					let p = Int32.to_int p in
					let i64 = Int64.logor (Int64.logand (Int64.of_int32 (get_i32 b p)) 0xFFFFFFFFL) (Int64.shift_left (Int64.of_int32 (get_i32 b (p + 4))) 32) in
					set r (VFloat (Int64.float_of_bits i64))
				| _ -> assert false)
			| OGetArray (r,a,i) ->
				(match get a, get i with
				| VArray (a,_), VInt i -> set r a.(Int32.to_int i)
				| _ -> assert false);
			| OSetI8 (r,p,v) ->
				(match get r, get p, get v with
				| VBytes b, VInt p, VInt v -> String.set b (Int32.to_int p) (char_of_int ((Int32.to_int v) land 0xFF))
				| _ -> assert false)
			| OSetI32 (r,p,v) ->
				(match get r, get p, get v with
				| VBytes b, VInt p, VInt v -> set_i32 b (Int32.to_int p) v
				| _ -> assert false)
			| OSetF32 (r,p,v) ->
				(match get r, get p, get v with
				| VBytes b, VInt p, VFloat v -> set_i32 b (Int32.to_int p) (Int32.bits_of_float v)
				| _ -> assert false)
			| OSetF64 (r,p,v) ->
				(match get r, get p, get v with
				| VBytes b, VInt p, VFloat v ->
					let p = Int32.to_int p in
					let v64 = Int64.bits_of_float v in
					set_i32 b p (Int64.to_int32 v64);
					set_i32 b (p + 4) (Int64.to_int32 (Int64.shift_right_logical v64 32));
				| _ -> assert false)
			| OSetArray (a,i,v) ->
				(match get a, get i with
				| VArray (a,t), VInt i ->
					let v = get v in
					check v t (fun() -> "array");
					a.(Int32.to_int i) <- v
				| _ -> assert false);
			| OSafeCast (r, v) ->
				set r (dyn_cast (get v) (rtype v) (rtype r))
			| OUnsafeCast (r,v) ->
				set r (get v)
			| OArraySize (r,a) ->
				(match get a with
				| VArray (a,_) -> set r (VInt (Int32.of_int (Array.length a)));
				| _ -> assert false)
			| OError s ->
				throw_msg code.strings.(s)
			| OType (r,t) ->
				set r (VType t)
			| OGetType (r,v) ->
				let v = get v in
				let v = (match v with VVirtual v -> v.vvalue | _ -> v) in
				set r (VType (if v = VNull then HVoid else match get_type v with None -> assert false | Some t -> t));
			| OGetTID (r,v) ->
				set r (match get v with
					| VType t ->
						(VInt (Int32.of_int (match t with
						| HVoid -> 0
						| HI8 -> 1
						| HI16 -> 2
						| HI32 -> 3
						| HF32 -> 4
						| HF64 -> 5
						| HBool -> 6
						| HBytes -> 7
						| HDyn -> 8
						| HFun _ -> 9
						| HObj _ -> 10
						| HArray -> 11
						| HType -> 12
						| HRef _ -> 13
						| HVirtual _ -> 14
						| HDynObj -> 15
						| HAbstract _ -> 16
						| HEnum _ -> 17
						| HNull _ -> 18)))
					| _ -> assert false);
			| ORef (r,v) ->
				set r (VRef (regs,v,rtype v))
			| OUnref (v,r) ->
				set v (match get r with
				| VRef (regs,i,_) -> Array.unsafe_get regs i
				| _ -> assert false)
			| OSetref (r,v) ->
				(match get r with
				| VRef (regs,i,t) ->
					let v = get v in
					check v t (fun() -> "ref");
					Array.unsafe_set regs i v
				| _ -> assert false)
			| OToVirtual (r,rv) ->
				set r (to_virtual (get rv) (match rtype r with HVirtual vp -> vp | _ -> assert false))
			| OUnVirtual (r,v) ->
				set r (match get v with VNull -> VNull | VVirtual v -> v.vvalue | _ -> assert false)
			| ODynGet (r,o,f) ->
				set r (dyn_get_field (get o) code.strings.(f) (rtype r))
			| ODynSet (o,fid,vr) ->
				dyn_set_field (get o) code.strings.(fid) (get vr) (rtype vr)
			| OMakeEnum (r,e,pl) ->
				set r (VEnum (e,Array.map get (Array.of_list pl)))
			| OEnumAlloc (r,f) ->
				(match rtype r with
				| HEnum e ->
					let _, _, fl = e.efields.(f) in
					let vl = Array.create (Array.length fl) VUndef in
					set r (VEnum (f, vl))
				| _ -> assert false
				)
			| OEnumIndex (r,v) ->
				(match get v with
				| VEnum (i,_) | VDyn (VEnum (i,_),_) -> set r (VInt (Int32.of_int i))
				| _ -> assert false)
			| OEnumField (r, v, _, i) ->
				(match get v with
				| VEnum (_,vl) -> set r vl.(i)
				| _ -> assert false)
			| OSetEnumField (v, i, r) ->
				(match get v, rtype v with
				| VEnum (id,vl), HEnum e ->
					let rv = get r in
					let _, _, fields = e.efields.(id) in
					check rv fields.(i) (fun() -> "enumfield");
					vl.(i) <- rv
				| _ -> assert false)
			| OSwitch (r, indexes) ->
				(match get r with
				| VInt i ->
					let i = Int32.to_int i in
					if i >= 0 && i < Array.length indexes then pos := !pos + indexes.(i)
				| _ -> assert false)
			| ONullCheck r ->
				if get r = VNull then throw_msg "Null access"
			| OTrap (r,j) ->
				let target = !pos + j in
				traps := (r,target) :: !traps
			| OEndTrap _ ->
				traps := List.tl !traps
			| ODump r ->
				print_endline (vstr_d (get r));
			);
			loop()
		in
		let rec exec() =
			try
				loop()
			with
				| Return v ->
					check v fret (fun() -> "return value");
					stack := List.tl !stack;
					v
				| InterpThrow v ->
					match !traps with
					| [] ->
						exc_stack := List.hd !stack :: !exc_stack;
						stack := List.tl !stack;
						raise (InterpThrow v)
					| (r,target) :: tl ->
						traps := tl;
						exc_stack := (f,ref !pos) :: !exc_stack;
						pos := target;
						set r v;
						exec()
		in
		pos := 0;
		exec()
	in
	let int = Int32.to_int in
	let to_int i = VInt (Int32.of_int i) in
	let date d =
		Unix.localtime (Int32.to_float d)
	in
	let to_date d =
		let t, _ = Unix.mktime d in
		VInt (Int32.of_float t)
	in
	let load_native lib name t =
		let unresolved() = (fun args -> error ("Unresolved native " ^ lib ^ "@" ^ name)) in
		let f = (match lib with
		| "std" ->
			(match name with
			| "balloc" ->
				(function
				| [VInt i] -> VBytes (String.create (int i))
				| _ -> assert false)
			| "aalloc" ->
				(function
				| [VType t;VInt i] -> VArray (Array.create (int i) (default t),t)
				| _ -> assert false)
			| "oalloc" ->
				(function
				| [VType t] -> alloc_obj t
				| _ -> assert false)
			| "ealloc" ->
				(function
				| [VType (HEnum e); VInt idx; VArray (vl,vt)] ->
					let idx = int idx in
					let _, _, args = e.efields.(idx) in
					if Array.length args <> Array.length vl then
						VNull
					else
						VDyn (VEnum (idx,Array.mapi (fun i v -> dyn_cast v vt args.(i)) vl),HEnum e)
				| _ -> assert false)
			| "ablit" ->
				(function
				| [VArray (dst,_); VInt dp; VArray (src,_); VInt sp; VInt len] ->
					Array.blit src (int sp) dst (int dp) (int len);
					VUndef
				| _ -> assert false)
			| "bblit" ->
				(function
				| [VBytes dst; VInt dp; VBytes src; VInt sp; VInt len] ->
					String.blit src (int sp) dst (int dp) (int len);
					VUndef
				| _ -> assert false)
			| "bsort_i32" ->
				(function
				| [VBytes b; VInt pos; VInt len; VClosure (f,c)] ->
					let pos = int pos and len = int len in
					let a = Array.init len (fun i -> get_i32 b (pos + i * 4)) in
					Array.stable_sort (fun a b ->
						match fcall f (match c with None -> [VInt a;VInt b] | Some v -> [v;VInt a;VInt b]) with
						| VInt i -> int i
						| _ -> assert false
					) a;
					Array.iteri (fun i v -> set_i32 b (pos + i * 4) v) a;
					VUndef;
				| _ ->
					assert false)
			| "bsort_f64" ->
				(function
				| [VBytes b; VInt pos; VInt len; VClosure _] ->
					assert false
				| _ ->
					assert false)
			| "itos" ->
				(function
				| [VInt v; VRef (regs,i,_)] ->
					let str = Int32.to_string v in
					regs.(i) <- to_int (String.length str);
					VBytes (caml_to_hl str)
				| _ -> assert false);
			| "ftos" ->
				(function
				| [VFloat _ as v; VRef (regs,i,_)] ->
					let str = vstr v HF64 in
					regs.(i) <- to_int (String.length str);
					VBytes (caml_to_hl str)
				| _ -> assert false);
			| "value_to_string" ->
				(function
				| [v; VRef (regs,i,_)] ->
					let str = caml_to_hl (vstr v HDyn) in
					regs.(i) <- to_int (String.length str - 2);
					VBytes str
				| _ -> assert false);
			| "math_isnan" -> (function [VFloat f] -> VBool (classify_float f = FP_nan) | _ -> assert false)
			| "math_isfinite" -> (function [VFloat f] -> VBool (match classify_float f with FP_infinite | FP_nan -> false | _ -> true) | _ -> assert false)
			| "math_round" -> (function [VFloat f] -> VInt (Int32.of_float (floor (f +. 0.5))) | _ -> assert false)
			| "math_floor" -> (function [VFloat f] -> VInt (Int32.of_float (floor f)) | _ -> assert false)
			| "math_ceil" -> (function [VFloat f] -> VInt (Int32.of_float (ceil f)) | _ -> assert false)
			| "math_ffloor" -> (function [VFloat f] -> VFloat (floor f) | _ -> assert false)
			| "math_fceil" -> (function [VFloat f] -> VFloat (ceil f) | _ -> assert false)
			| "math_fround" -> (function [VFloat f] -> VFloat (floor (f +. 0.5)) | _ -> assert false)
			| "math_abs" -> (function [VFloat f] -> VFloat (abs_float f) | _ -> assert false)
			| "math_sqrt" -> (function [VFloat f] -> VFloat (sqrt f) | _ -> assert false)
			| "math_cos" -> (function [VFloat f] -> VFloat (cos f) | _ -> assert false)
			| "math_sin" -> (function [VFloat f] -> VFloat (sin f) | _ -> assert false)
			| "math_tan" -> (function [VFloat f] -> VFloat (tan f) | _ -> assert false)
			| "math_acos" -> (function [VFloat f] -> VFloat (acos f) | _ -> assert false)
			| "math_asin" -> (function [VFloat f] -> VFloat (asin f) | _ -> assert false)
			| "math_atan" -> (function [VFloat f] -> VFloat (atan f) | _ -> assert false)
			| "math_atan2" -> (function [VFloat a; VFloat b] -> VFloat (atan2 a b) | _ -> assert false)
			| "math_log" -> (function [VFloat f] -> VFloat (Pervasives.log f) | _ -> assert false)
			| "math_exp" -> (function [VFloat f] -> VFloat (exp f) | _ -> assert false)
			| "math_pow" -> (function [VFloat a; VFloat b] -> VFloat (a ** b) | _ -> assert false)
			| "parse_int" ->
				(function
				| [VBytes str; VInt pos; VInt len] ->
					(try
						let i = (match Interp.parse_int (hl_to_caml_sub str (int pos) (int len)) with
							| Interp.VInt v -> Int32.of_int v
							| Interp.VInt32 v -> v
							| _ -> assert false
						) in
						VDyn (VInt i,HI32)
					with _ ->
						VNull)
				| l -> assert false)
			| "parse_float" ->
				(function
				| [VBytes str; VInt pos; VInt len] -> (try VFloat (Interp.parse_float (hl_to_caml_sub str (int pos) (int len))) with _ -> VFloat nan)
				| _ -> assert false)
			| "dyn_compare" ->
				(function
				| [a;b] -> to_int (dyn_compare a HDyn b HDyn)
				| _ -> assert false)
			| "fun_compare" ->
				let ocompare o1 o2 =
					match o1, o2 with
					| None, None -> true
					| Some o1, Some o2 -> o1 == o2
					| _ -> false
				in
				(function
				| [VClosure (FFun f1,o1);VClosure (FFun f2,o2)] -> VBool (f1 == f2 && ocompare o1 o2)
				| [VClosure (FNativeFun (f1,_,_),o1);VClosure (FNativeFun (f2,_,_),o2)] -> VBool (f1 = f2 && ocompare o1 o2)
				| _ -> VBool false)
			| "atype" ->
				(function
				| [VArray (_,t)] -> VType t
				| _ -> assert false)
			| "safe_cast" ->
				(function
				| [v;VType t] -> if is_compatible v t then v else throw_msg ("Cannot cast " ^ vstr_d v ^ " to " ^ tstr t);
				| _ -> assert false)
			| "hballoc" ->
				(function
				| [] -> VAbstract (AHashBytes (Hashtbl.create 0))
				| _ -> assert false)
			| "hbset" ->
				(function
				| [VAbstract (AHashBytes h);VBytes b;v] ->
					Hashtbl.replace h (hl_to_caml b) v;
					VUndef
				| _ -> assert false)
			| "hbget" ->
				(function
				| [VAbstract (AHashBytes h);VBytes b] ->
					(try Hashtbl.find h (hl_to_caml b) with Not_found -> VNull)
				| _ -> assert false)
			| "hbvalues" ->
				(function
				| [VAbstract (AHashBytes h)] ->
					let values = Hashtbl.fold (fun _ v acc -> v :: acc) h [] in
					VArray (Array.of_list values, HDyn)
				| _ -> assert false)
			| "hbkeys" ->
				(function
				| [VAbstract (AHashBytes h)] ->
					let keys = Hashtbl.fold (fun s _ acc -> VBytes (caml_to_hl s) :: acc) h [] in
					VArray (Array.of_list keys, HBytes)
				| _ -> assert false)
			| "hbexists" ->
				(function
				| [VAbstract (AHashBytes h);VBytes b] -> VBool (Hashtbl.mem h (hl_to_caml b))
				| _ -> assert false)
			| "hbremove" ->
				(function
				| [VAbstract (AHashBytes h);VBytes b] ->
					let m = Hashtbl.mem h (hl_to_caml b) in
					if m then Hashtbl.remove h (hl_to_caml b);
					VBool m
				| _ -> assert false)
			| "hialloc" ->
				(function
				| [] -> VAbstract (AHashInt (Hashtbl.create 0))
				| _ -> assert false)
			| "hiset" ->
				(function
				| [VAbstract (AHashInt h);VInt i;v] ->
					Hashtbl.replace h i v;
					VUndef
				| _ -> assert false)
			| "higet" ->
				(function
				| [VAbstract (AHashInt h);VInt i] ->
					(try Hashtbl.find h i with Not_found -> VNull)
				| _ -> assert false)
			| "hivalues" ->
				(function
				| [VAbstract (AHashInt h)] ->
					let values = Hashtbl.fold (fun _ v acc -> v :: acc) h [] in
					VArray (Array.of_list values, HDyn)
				| _ -> assert false)
			| "hikeys" ->
				(function
				| [VAbstract (AHashInt h)] ->
					let keys = Hashtbl.fold (fun i _ acc -> VInt i :: acc) h [] in
					VArray (Array.of_list keys, HI32)
				| _ -> assert false)
			| "hiexists" ->
				(function
				| [VAbstract (AHashInt h);VInt i] -> VBool (Hashtbl.mem h i)
				| _ -> assert false)
			| "hiremove" ->
				(function
				| [VAbstract (AHashInt h);VInt i] ->
					let m = Hashtbl.mem h i in
					if m then Hashtbl.remove h i;
					VBool m
				| _ -> assert false)
			| "hoalloc" ->
				(function
				| [] -> VAbstract (AHashObject (ref []))
				| _ -> assert false)
			| "hoset" ->
				(function
				| [VAbstract (AHashObject l);o;v] ->
					let rec replace l =
						match l with
						| [] -> [o,v]
						| (o2,_) :: l when o == o2 -> (o,v) :: l
						| p :: l -> p :: replace l
					in
					l := replace !l;
					VUndef
				| _ -> assert false)
			| "hoget" ->
				(function
				| [VAbstract (AHashObject l);o] ->
					(try List.assq o !l with Not_found -> VNull)
				| _ -> assert false)
			| "hovalues" ->
				(function
				| [VAbstract (AHashObject l)] ->
					VArray (Array.of_list (List.map snd !l), HDyn)
				| _ -> assert false)
			| "hokeys" ->
				(function
				| [VAbstract (AHashObject l)] ->
					VArray (Array.of_list (List.map fst !l), HDyn)
				| _ -> assert false)
			| "hoexists" ->
				(function
				| [VAbstract (AHashObject l);o] -> VBool (List.mem_assq o !l)
				| _ -> assert false)
			| "horemove" ->
				(function
				| [VAbstract (AHashObject rl);o] ->
					let rec loop acc = function
						| [] -> false
						| (o2,_) :: l when o == o2 ->
							rl := (List.rev acc) @ l;
							true
						| p :: l -> loop (p :: acc) l
					in
					VBool (loop [] !rl)
				| _ -> assert false)
			| "sys_print" ->
				(function
				| [VBytes str] -> print_string (hl_to_caml str); VUndef
				| _ -> assert false)
			| "sys_time" ->
				(function
				| [] -> VFloat (Unix.time())
				| _ -> assert false)
			| "sys_exit" ->
				(function
				| [VInt code] -> VUndef
				| _ -> assert false)
			| "hash" ->
				(function
				| [VBytes str] -> VInt (hash (hl_to_caml str))
				| _ -> assert false)
			| "type_check" ->
				(function
				| [VType t;v] ->
					if t = HDyn then VBool true else
					if v = VNull then VBool false else
					(match get_type v with
					| None -> assert false
					| Some (HI8|HI16|HI32) when (match t with HF32 | HF64 -> true | _ -> false) -> VBool true
					| Some (HF32|HF64) when (match t, v with (HI8|HI16|HI32), VDyn (VFloat f,_) -> Int32.to_float (Int32.of_float f) = f | _ -> false) -> VBool true
					| Some vt ->
						VBool (safe_cast vt t))
				| _ -> assert false)
			| "type_instance" ->
				(function
				| [VType t;v] -> if v = VNull then v else (match get_type v with None -> assert false | Some vt -> if safe_cast vt t then v else VNull)
				| _ -> assert false)
			| "type_super" ->
				(function
				| [VType t] -> VType (match t with HObj { psuper = Some o } -> HObj o | _ -> HVoid)
				| _ -> assert false)
			| "type_args_count" ->
				(function
				| [VType t] -> to_int (match t with HFun (args,_) -> List.length args | _ -> 0)
				| _ -> assert false)
			| "type_get_global" ->
				(function
				| [VType t] ->
					(match t with
					| HObj c -> (match c.pclassglobal with None -> VNull | Some g -> globals.(g))
					| HEnum e -> globals.(e.eglobal)
					| _ -> VNull)
				| _ -> assert false)
			| "type_name" ->
				(function
				| [VType t] ->
					VBytes (caml_to_hl (match t with
					| HObj o -> o.pname
					| HEnum e -> e.ename
					| _ -> assert false))
				| _ -> assert false)
			| "obj_fields" ->
				(function
				| [VDynObj o; VBool _] ->
					VArray (Array.of_list (Hashtbl.fold (fun n _ acc -> VBytes (caml_to_hl n) :: acc) o.dfields []), HBytes)
				| [VObj o; VBool isRec] ->
					let rec loop p =
						let fields = Array.map (fun (n,_,_) -> VBytes (caml_to_hl n)) p.pfields in
						match p.psuper with Some p when isRec -> fields :: loop p | _ -> [fields]
					in
					VArray (Array.concat (loop o.oproto.pclass), HBytes)
				| _ ->
					VNull)
			| "obj_copy" ->
				(function
				| [VDynObj d] ->
					VDynObj { dfields = Hashtbl.copy d.dfields; dvalues = Array.copy d.dvalues; dtypes = Array.copy d.dtypes; dvirtuals = [] }
				| [_] -> VNull
				| _ -> assert false)
			| "enum_parameters" ->
				(function
				| [VDyn (VEnum (idx,pl),HEnum e)] ->
					let _,_, ptypes = e.efields.(idx) in
					VArray (Array.mapi (fun i v -> make_dyn v ptypes.(i)) pl,HDyn)
				| _ ->
					assert false)
			| "type_instance_fields" ->
				(function
				| [VType t] ->
					(match t with
					| HObj o ->
						let rec fields o =
							let sup = (match o.psuper with None -> [||] | Some o -> fields o) in
							Array.concat [
								sup;
								Array.map (fun (s,_,_) -> VBytes (caml_to_hl s)) o.pfields;
								Array.of_list (Array.fold_left (fun acc f ->
									let is_override = (match o.psuper with None -> false | Some p -> try ignore(get_index f.fname p); true with Not_found -> false) in
									if is_override then acc else VBytes (caml_to_hl f.fname) :: acc
								) [] o.pproto)
							]
						in
						VArray (fields o,HBytes)
					| _ -> VNull)
				| _ -> assert false)
			| "type_enum_fields" ->
				(function
				| [VType t] ->
					(match t with
					| HEnum e -> VArray (Array.map (fun (f,_,_) -> VBytes (caml_to_hl f)) e.efields,HBytes)
					| _ -> VNull)
				| _ -> assert false)
			| "type_enum_eq" ->
				(function
				| [VDyn (VEnum _, HEnum _); VNull] | [VNull; VDyn (VEnum _, HEnum _)] -> VBool false
				| [VNull; VNull] -> VBool true
				| [VDyn (VEnum _ as v1, HEnum e1); VDyn (VEnum _ as v2, HEnum e2)] ->
					let rec loop v1 v2 e =
						match v1, v2 with
						| VEnum (t1,_), VEnum (t2,_) when t1 <> t2 -> false
						| VEnum (t,vl1), VEnum (_,vl2) ->
							let _, _, pl = e.efields.(t) in
							let rec chk i =
								if i = Array.length pl then true
								else
								(match pl.(i) with
								| HEnum e -> loop vl1.(i) vl2.(i) e
								| t -> dyn_compare vl1.(i) t vl2.(i) t = 0) && chk (i + 1)
							in
							chk 0
						| _ -> assert false
					in
					VBool (if e1 != e2 then false else loop v1 v2 e1)
				| _ -> assert false)
			| "obj_get_field" ->
				(function
				| [o;VInt hash] ->
					let f = (try Hashtbl.find hash_cache hash with Not_found -> assert false) in
					(match o with
					| VObj _ | VDynObj _ | VVirtual _ -> dyn_get_field o f HDyn
					| _ -> VNull)
				| _ -> assert false)
			| "obj_set_field" ->
				(function
				| [o;VInt hash;v] ->
					let f = (try Hashtbl.find hash_cache hash with Not_found -> assert false) in
					dyn_set_field o f v HDyn;
					VUndef
				| _ -> assert false)
			| "obj_has_field" ->
				(function
				| [o;VInt hash] ->
					let f = (try Hashtbl.find hash_cache hash with Not_found -> assert false) in
					let rec loop o =
						match o with
						| VDynObj d -> Hashtbl.mem d.dfields f
						| VObj o ->
							let rec loop p =
								if PMap.mem f p.pindex then let idx, _ = PMap.find f p.pindex in idx >= 0 else match p.psuper with None -> false | Some p -> loop p
							in
							loop o.oproto.pclass
						| VVirtual v -> loop v.vvalue
						| _ -> false
					in
					VBool (loop o)
				| _ -> assert false)
			| "obj_delete_field" ->
				(function
				| [o;VInt hash] ->
					let f = (try Hashtbl.find hash_cache hash with Not_found -> assert false) in
					let rec loop o =
						match o with
						| VDynObj d when Hashtbl.mem d.dfields f ->
							let idx = Hashtbl.find d.dfields f in
							let count = Array.length d.dvalues in
							Hashtbl.remove d.dfields f;
							let fields = Hashtbl.fold (fun name i acc -> (name,if i < idx then i else i - 1) :: acc) d.dfields [] in
							Hashtbl.clear d.dfields;
							List.iter (fun (n,i) -> Hashtbl.add d.dfields n i) fields;
							let vals2 = Array.make (count - 1) VNull in
							let types2 = Array.make (count - 1) HVoid in
							let len = count - idx - 1 in
							Array.blit d.dvalues 0 vals2 0 idx;
							Array.blit d.dvalues (idx + 1) vals2 idx len;
							Array.blit d.dtypes 0 types2 0 idx;
							Array.blit d.dtypes (idx + 1) types2 idx len;
							d.dvalues <- vals2;
							d.dtypes <- types2;
							rebuild_virtuals d;
							true
						| VVirtual v -> loop v.vvalue
						| _ -> false
					in
					VBool (loop o)
				| _ -> assert false)
			| "ucs2length" ->
				(function
				| [VBytes s; VInt pos] ->
					let delta = int pos in
					let rec loop p =
						let c = int_of_char s.[p+delta] lor ((int_of_char s.[p+delta+1]) lsl 8) in
						if c = 0 then p lsr 1 else loop (p + 2)
					in
					to_int (loop 0)
				| _ -> assert false)
			| "utf8_to_utf16" ->
				(function
				| [VBytes s; VInt pos; VRef (regs,idx,HI32)] ->
					let s = String.sub s (int pos) (String.length s - (int pos)) in
					let u16 = caml_to_hl (try String.sub s 0 (String.index s '\000') with Not_found -> assert false) in
					regs.(idx) <- to_int (String.length u16 - 2);
					VBytes u16
				| _ -> assert false)
			| "utf16_to_utf8" ->
				(function
				| [VBytes s; VInt pos; VRef (regs,idx,HI32)] ->
					let s = String.sub s (int pos) (String.length s - (int pos)) in
					let u8 = hl_to_caml s in
					regs.(idx) <- to_int (String.length u8);
					VBytes (u8 ^ "\x00")
				| _ -> assert false)
			| "ucs2_upper" ->
				(function
				| [VBytes s; VInt pos; VInt len] ->
					let buf = Buffer.create 0 in
					utf16_iter (fun c ->
						let c =
							if c >= int_of_char 'a' && c <= int_of_char 'z' then c + int_of_char 'A' - int_of_char 'a'
							else c
						in
						utf16_add buf c
					) (String.sub s (int pos) (int len));
					utf16_add buf 0;
					VBytes (Buffer.contents buf)
				| _ -> assert false)
			| "ucs2_lower" ->
				(function
				| [VBytes s; VInt pos; VInt len] ->
					let buf = Buffer.create 0 in
					utf16_iter (fun c ->
						let c =
							if c >= int_of_char 'A' && c <= int_of_char 'Z' then c + int_of_char 'a' - int_of_char 'A'
							else c
						in
						utf16_add buf c
					) (String.sub s (int pos) (int len));
					utf16_add buf 0;
					VBytes (Buffer.contents buf)
				| _ -> assert false)
			| "url_encode" ->
				(function
				| [VBytes s; VRef (regs, idx, HI32)] ->
					let s = hl_to_caml s in
					let buf = Buffer.create 0 in
					let hex = "0123456789ABCDEF" in
					for i = 0 to String.length s - 1 do
						let c = String.unsafe_get s i in
						match c with
						| 'A'..'Z' | 'a'..'z' | '0'..'9' | '_' | '-' | '.' ->
							utf16_char buf c
						| _ ->
							utf16_char buf '%';
							utf16_char buf (String.unsafe_get hex (int_of_char c lsr 4));
							utf16_char buf (String.unsafe_get hex (int_of_char c land 0xF));
					done;
					utf16_add buf 0;
					let str = Buffer.contents buf in
					regs.(idx) <- to_int (String.length str lsr 1 - 1);
					VBytes str
				| _ -> assert false)
			| "url_decode" ->
				(function
				| [VBytes s; VRef (regs, idx, HI32)] ->
					let s = hl_to_caml s in
					let b = Buffer.create 0 in
					let len = String.length s in
					let decode c =
						match c with
						| '0'..'9' -> Some (int_of_char c - int_of_char '0')
						| 'a'..'f' -> Some (int_of_char c - int_of_char 'a' + 10)
						| 'A'..'F' -> Some (int_of_char c - int_of_char 'A' + 10)
						| _ -> None
					in
					let rec loop i =
						if i = len then () else
						let c = String.unsafe_get s i in
						match c with
						| '%' ->
							let p1 = (try decode (String.get s (i + 1)) with _ -> None) in
							let p2 = (try decode (String.get s (i + 2)) with _ -> None) in
							(match p1, p2 with
							| Some c1, Some c2 ->
								Buffer.add_char b (char_of_int ((c1 lsl 4) lor c2));
								loop (i + 3)
							| _ ->
								loop (i + 1));
						| '+' ->
							Buffer.add_char b ' ';
							loop (i + 1)
						| c ->
							Buffer.add_char b c;
							loop (i + 1)
					in
					loop 0;
					let str = Buffer.contents b in
					regs.(idx) <- to_int (UTF8.length str);
					VBytes (caml_to_hl str)
				| _ -> assert false)
			| "call_method" ->
				(function
				| [f;VArray (args,HDyn)] -> dyn_call f (List.map (fun v -> v,HDyn) (Array.to_list args)) HDyn
				| _ -> assert false)
			| "no_closure" ->
				(function
				| [VClosure (f,_)] -> VClosure (f,None)
				| _ -> assert false)
			| "get_closure_value" ->
				(function
				| [VClosure (_,None)] -> VNull
				| [VClosure (_,Some v)] -> v
				| _ -> assert false)
			| "make_var_args" ->
				(function
				| [VClosure (f,arg)] -> VVarArgs (f,arg)
				| _ -> assert false)
			| "bytes_find" ->
				(function
				| [VBytes src; VInt pos; VInt len; VBytes chk; VInt cpos; VInt clen; ] ->
					to_int (try int pos + ExtString.String.find (String.sub src (int pos) (int len)) (String.sub chk (int cpos) (int clen)) with ExtString.Invalid_string -> -1)
				| _ -> assert false)
			| "bytes_compare" ->
				(function
				| [VBytes a; VInt apos; VBytes b; VInt bpos; VInt len] -> to_int (String.compare (String.sub a (int apos) (int len)) (String.sub b (int bpos) (int len)))
				| _ -> assert false)
			| "bytes_fill" ->
				(function
				| [VBytes a; VInt pos; VInt len; VInt v] ->
					String.fill a (int pos) (int len) (char_of_int ((int v) land 0xFF));
					VUndef
				| _ -> assert false)
			| "date_new" ->
				(function
				| [VInt y; VInt mo; VInt d; VInt h; VInt m; VInt s] ->
					let t = Unix.localtime (Unix.time()) in
					let t = { t with
						tm_year = int y - 1900;
						tm_mon = int mo;
						tm_mday = int d;
						tm_hour = int h;
						tm_min = int m;
						tm_sec = int s;
					} in
					to_date t
				| _ ->
					assert false)
			| "date_now" ->
				(function
				| [] -> to_date (Unix.localtime (Unix.time()))
				| _ -> assert false)
			| "date_get_time" ->
				(function
				| [VInt v] -> VFloat (fst (Unix.mktime (date v)) *. 1000.)
				| _ -> assert false)
			| "date_from_time" ->
				(function
				| [VFloat f] -> to_date (Unix.localtime (f /. 1000.))
				| _ -> assert false)
			| "date_get_weekday" ->
				(function
				| [VInt d] ->
					let d = date d in
					to_int d.tm_wday
				| _ -> assert false)
			| "date_get_inf" ->
				(function
				| [VInt d;year;month;day;hours;minutes;seconds] ->
					let d = date d in
					let set r v =
						match r with
						| VNull -> ()
						| VRef (regs,pos,HI32) -> regs.(pos) <- to_int v
						| _ -> assert false
					in
					set year (d.tm_year + 1900);
					set month d.tm_mon;
					set day d.tm_mday;
					set hours d.tm_hour;
					set minutes d.tm_min;
					set seconds d.tm_sec;
					VUndef
				| _ -> assert false)
			| "date_to_string" ->
				(function
				| [VInt d; VRef (regs,pos,HI32)] ->
					let t = date d in
					let str = Printf.sprintf "%.4d-%.2d-%.2d %.2d:%.2d:%.2d" (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec in
					regs.(pos) <- to_int (String.length str);
					VBytes (caml_to_hl str)
				| _ -> assert false)
			| "random" ->
				(function
				| [VInt max] -> VInt (if max <= 0l then 0l else Random.int32 max)
				| _ -> assert false)
			| _ ->
				unresolved())
		| "regexp" ->
			(match name with
			| "regexp_new_options" ->
				(function
				| [VBytes str; VBytes opt] ->
					let case_sensitive = ref true in
					List.iter (function
						| 'm' -> () (* always ON ? *)
						| 'i' -> case_sensitive := false
						| c -> failwith ("Unsupported regexp option '" ^ String.make 1 c ^ "'")
					) (ExtString.String.explode (hl_to_caml opt));
					let buf = Buffer.create 0 in
					let rec loop prev esc = function
						| [] -> ()
						| c :: l when esc ->
							(match c with
							| 'n' -> Buffer.add_char buf '\n'
							| 'r' -> Buffer.add_char buf '\r'
							| 't' -> Buffer.add_char buf '\t'
							| 's' -> Buffer.add_string buf "[ \t\r\n]"
							| 'd' -> Buffer.add_string buf "[0-9]"
							| '\\' -> Buffer.add_string buf "\\\\"
							| '(' | ')' | '{' | '}' -> Buffer.add_char buf c
							| '1'..'9' | '+' | '$' | '^' | '*' | '?' | '.' | '[' | ']' ->
								Buffer.add_char buf '\\';
								Buffer.add_char buf c;
							| _ -> failwith ("Unsupported escaped char '" ^ String.make 1 c ^ "'"));
							loop c false l
						| c :: l ->
							match c with
							| '\\' -> loop prev true l
							| '(' | '|' | ')' ->
								Buffer.add_char buf '\\';
								Buffer.add_char buf c;
								loop c false l
							| '?' when prev = '(' && (match l with ':' :: _ -> true | _ -> false) ->
								failwith "Non capturing groups '(?:' are not supported in macros"
							| '?' when prev = '*' ->
								failwith "Ungreedy *? are not supported in macros"
							| _ ->
								Buffer.add_char buf c;
								loop c false l
					in
					loop '\000' false (ExtString.String.explode (hl_to_caml str));
					let str = Buffer.contents buf in
					let r = {
						r = if !case_sensitive then Str.regexp str else Str.regexp_case_fold str;
						r_string = "";
						r_groups = [||];
					} in
					VAbstract (AReg r)
				| _ ->
					assert false);
			| "regexp_match" ->
				(function
				| [VAbstract (AReg r);VBytes str;VInt pos;VInt len] ->
					let str = hl_to_caml str and pos = int pos and len = int len in
					let nstr, npos, delta = (if len = String.length str - pos then str, pos, 0 else String.sub str pos len, 0, pos) in
					(try
						ignore(Str.search_forward r.r nstr npos);
						let rec loop n =
							if n = 9 then
								[]
							else try
								(Some (Str.group_beginning n + delta, Str.group_end n + delta)) :: loop (n + 1)
							with Not_found ->
								None :: loop (n + 1)
							| Invalid_argument _ ->
								[]
						in
						r.r_string <- str;
						r.r_groups <- Array.of_list (loop 0);
						VBool true;
					with Not_found ->
						VBool false)
				| _ -> assert false);
			| "regexp_matched_pos" ->
				(function
				| [VAbstract (AReg r); VInt n; VRef (regs,rlen,HI32)] ->
					let n = int n in
					(match (try r.r_groups.(n) with _ -> failwith ("Invalid group " ^ string_of_int n)) with
					| None -> to_int (-1)
					| Some (pos,pend) -> regs.(rlen) <- to_int (pend - pos); to_int pos)
				| _ -> assert false)
			| "regexp_matched" ->
				(function
				| [VAbstract (AReg r); VInt n; VRef (regs,rlen,HI32)] ->
					let n = int n in
					(match (try r.r_groups.(n) with _ -> failwith ("Invalid group " ^ string_of_int n)) with
					| None -> VNull
					| Some (pos,pend) ->
						regs.(rlen) <- to_int (pend - pos);
						VBytes (caml_to_hl (String.sub r.r_string pos (pend - pos))))
				| _ -> assert false)
			| _ ->
				unresolved())
		| _ ->
			unresolved()
		) in
		FNativeFun (lib ^ "@" ^ name, f, t)
	in
	Array.iter (fun (lib,name,t,idx) -> functions.(idx) <- load_native code.strings.(lib) code.strings.(name) t) code.natives;
	Array.iter (fun fd -> functions.(fd.findex) <- FFun fd) code.functions;
	let get_stack st =
		String.concat "\n" (List.map (fun (f,pos) ->
			let pos = !pos - 1 in
			let file, line = (try let fid, line = f.debug.(pos) in code.debugfiles.(fid), line with _ -> "???", 0) in
			Printf.sprintf "%s:%d: Called from fun(%d)@%d" file line f.findex pos
		) st)
	in
	match functions.(code.entrypoint) with
	| FFun f when f.ftype = HFun([],HVoid) ->
		(try
			ignore(call f [])
		with
			| InterpThrow v -> Common.error ("Uncaught exception " ^ vstr v HDyn ^ "\n" ^ get_stack (List.rev !exc_stack)) Ast.null_pos
			| Runtime_error msg -> Common.error ("HL Interp error " ^ msg ^ "\n" ^ get_stack !stack) Ast.null_pos
		)
	| _ -> assert false

(* --------------------------------------------------------------------------------------------------------------------- *)
(* WRITE *)


(* 	from -500M to +500M
	0[7] = 0-127
	10[+/-][5] [8] = -x2000/+x2000
	11[+/-][5] [24] = -x20000000/+x20000000
*)
let write_index_gen b i =
	if i < 0 then
		let i = -i in
		if i < 0x2000 then begin
			b ((i lsr 8) lor 0xA0);
			b (i land 0xFF);
		end else if i >= 0x20000000 then assert false else begin
			b ((i lsr 24) lor 0xE0);
			b ((i lsr 16) land 0xFF);
			b ((i lsr 8) land 0xFF);
			b (i land 0xFF);
		end
	else if i < 0x80 then
		b i
	else if i < 0x2000 then begin
		b ((i lsr 8) lor 0x80);
		b (i land 0xFF);
	end else if i >= 0x20000000 then assert false else begin
		b ((i lsr 24) lor 0xC0);
		b ((i lsr 16) land 0xFF);
		b ((i lsr 8) land 0xFF);
		b (i land 0xFF);
	end

let write_code ch code =

	let types = gather_types code in
	let byte = IO.write_byte ch in
	let write_index = write_index_gen byte in

	let rec write_type t =
		write_index (lookup types t (fun() -> assert false))
	in

	let write_op op =

		let o = Obj.repr op in
		let oid = Obj.tag o in

		match op with
		| OLabel _ | OEndTrap _ ->
			byte oid
		| OCall2 (r,g,a,b) ->
			byte oid;
			write_index r;
			write_index g;
			write_index a;
			write_index b;
		| OCall3 (r,g,a,b,c) ->
			byte oid;
			write_index r;
			write_index g;
			write_index a;
			write_index b;
			write_index c;
		| OCall4 (r,g,a,b,c,d) ->
			byte oid;
			write_index r;
			write_index g;
			write_index a;
			write_index b;
			write_index c;
			write_index d;
		| OCallN (r,f,rl) | OCallClosure (r,f,rl) | OCallMethod (r,f,rl) | OCallThis (r,f,rl) | OMakeEnum (r,f,rl) ->
			byte oid;
			write_index r;
			write_index f;
			let n = List.length rl in
			if n > 0xFF then assert false;
			byte n;
			List.iter write_index rl
		| OType (r,t) ->
			byte oid;
			write_index r;
			write_type t
		| OSwitch (r,pl) ->
			byte oid;
			let n = Array.length pl in
			if n > 0xFF then assert false;
			byte n;
			Array.iter write_index pl
		| OEnumField (r,e,i,idx) ->
			byte oid;
			write_index r;
			write_index e;
			write_index i;
			write_index idx;
		| _ ->
			let field n = (Obj.magic (Obj.field o n) : int) in
			match Obj.size o with
			| 1 ->
				let a = field 0 in
				byte oid;
				write_index a;
			| 2 ->
				let a = field 0 in
				let b = field 1 in
				byte oid;
				write_index a;
				write_index b;
			| 3 ->
				let a = field 0 in
				let b = field 1 in
				let c = field 2 in
				byte oid;
				write_index a;
				write_index b;
				write_index c;
			| _ ->
				assert false
	in

	IO.nwrite ch "HLB";
	IO.write_byte ch code.version;

	write_index (Array.length code.ints);
	write_index (Array.length code.floats);
	write_index (Array.length code.strings);
	write_index (DynArray.length types.arr);
	write_index (Array.length code.globals);
	write_index (Array.length code.natives);
	write_index (Array.length code.functions);
	write_index code.entrypoint;

	Array.iter (IO.write_real_i32 ch) code.ints;
	Array.iter (IO.write_double ch) code.floats;

	let str_length = ref 0 in
	Array.iter (fun str -> str_length := !str_length + String.length str + 1) code.strings;
	IO.write_i32 ch !str_length;
	Array.iter (IO.write_string ch) code.strings;
	Array.iter (fun str -> write_index (String.length str)) code.strings;

	DynArray.iter (fun t ->
		match t with
		| HVoid -> byte 0
		| HI8 -> byte 1
		| HI16 -> byte 2
		| HI32 -> byte 3
		| HF32 -> byte 4
		| HF64 -> byte 5
		| HBool -> byte 6
		| HBytes -> byte 7
		| HDyn -> byte 8
		| HFun (args,ret) ->
			let n = List.length args in
			if n > 0xFF then assert false;
			byte 9;
			byte n;
			List.iter write_type args;
			write_type ret
		| HObj p ->
			byte 10;
			write_index p.pid;
			(match p.psuper with
			| None -> write_index (-1)
			| Some t -> write_type (HObj t));
			write_index (Array.length p.pfields);
			write_index (Array.length p.pproto);
			Array.iter (fun (_,n,t) -> write_index n; write_type t) p.pfields;
			Array.iter (fun f -> write_index f.fid; write_index f.fmethod; write_index (match f.fvirtual with None -> -1 | Some i -> i)) p.pproto;
		| HArray ->
			byte 11
		| HType ->
			byte 12
		| HRef t ->
			byte 13;
			write_type t
		| HVirtual v ->
			byte 14;
			write_index (Array.length v.vfields);
			Array.iter (fun (_,sid,t) -> write_index sid; write_type t) v.vfields
		| HDynObj ->
			byte 15
		| HAbstract (_,i) ->
			byte 16;
			write_index i
		| HEnum e ->
			byte 17;
			write_index e.eid;
			write_index (Array.length e.efields);
			Array.iter (fun (_,n,tl) ->
				write_index (Array.length tl);
				Array.iter write_type tl;
			) e.efields
		| HNull t ->
			byte 0x18;
			write_type t
	) types.arr;

	Array.iter write_type code.globals;
	Array.iter (fun (lib_index, name_index,ttype,findex) ->
		write_index lib_index;
		write_index name_index;
		write_type ttype;
		write_index findex;
	) code.natives;
	Array.iter (fun f ->
		write_type f.ftype;
		write_index f.findex;
		write_index (Array.length f.regs);
		write_index (Array.length f.code);
		Array.iter write_type f.regs;
		Array.iter write_op f.code;
	) code.functions

(* --------------------------------------------------------------------------------------------------------------------- *)
(* DUMP *)

let ostr o =
	match o with
	| OMov (a,b) -> Printf.sprintf "mov %d,%d" a b
	| OInt (r,i) -> Printf.sprintf "int %d,@%d" r i
	| OFloat (r,i) -> Printf.sprintf "float %d,@%d" r i
	| OString (r,s) -> Printf.sprintf "string %d,@%d" r s
	| OBytes (r,s) -> Printf.sprintf "bytes %d,@%d" r s
	| OBool (r,b) -> if b then Printf.sprintf "true %d" r else Printf.sprintf "false %d" r
	| ONull r -> Printf.sprintf "null %d" r
	| OAdd (r,a,b) -> Printf.sprintf "add %d,%d,%d" r a b
	| OSub (r,a,b) -> Printf.sprintf "sub %d,%d,%d" r a b
	| OMul (r,a,b) -> Printf.sprintf "mul %d,%d,%d" r a b
	| OSDiv (r,a,b) -> Printf.sprintf "sdiv %d,%d,%d" r a b
	| OUDiv (r,a,b) -> Printf.sprintf "udiv %d,%d,%d" r a b
	| OSMod (r,a,b) -> Printf.sprintf "smod %d,%d,%d" r a b
	| OUMod (r,a,b) -> Printf.sprintf "umod %d,%d,%d" r a b
	| OShl (r,a,b) -> Printf.sprintf "shl %d,%d,%d" r a b
	| OSShr (r,a,b) -> Printf.sprintf "sshr %d,%d,%d" r a b
	| OUShr (r,a,b) -> Printf.sprintf "ushr %d,%d,%d" r a b
	| OAnd (r,a,b) -> Printf.sprintf "and %d,%d,%d" r a b
	| OOr (r,a,b) -> Printf.sprintf "or %d,%d,%d" r a b
	| OXor (r,a,b) -> Printf.sprintf "xor %d,%d,%d" r a b
	| ONeg (r,v) -> Printf.sprintf "neg %d,%d" r v
	| ONot (r,v) -> Printf.sprintf "not %d,%d" r v
	| OIncr r -> Printf.sprintf "incr %d" r
	| ODecr r -> Printf.sprintf "decr %d" r
	| OCall0 (r,g) -> Printf.sprintf "call %d, f%d()" r g
	| OCall1 (r,g,a) -> Printf.sprintf "call %d, f%d(%d)" r g a
	| OCall2 (r,g,a,b) -> Printf.sprintf "call %d, f%d(%d,%d)" r g a b
	| OCall3 (r,g,a,b,c) -> Printf.sprintf "call %d, f%d(%d,%d,%d)" r g a b c
	| OCall4 (r,g,a,b,c,d) -> Printf.sprintf "call %d, f%d(%d,%d,%d,%d)" r g a b c d
	| OCallN (r,g,rl) -> Printf.sprintf "call %d, f%d(%s)" r g (String.concat "," (List.map string_of_int rl))
	| OCallMethod (r,f,[]) -> "callmethod ???"
	| OCallMethod (r,f,o :: rl) -> Printf.sprintf "callmethod %d, %d[%d](%s)" r o f (String.concat "," (List.map string_of_int rl))
	| OCallClosure (r,f,rl) -> Printf.sprintf "callclosure %d, %d(%s)" r f (String.concat "," (List.map string_of_int rl))
	| OCallThis (r,f,rl) -> Printf.sprintf "callthis %d, [%d](%s)" r f (String.concat "," (List.map string_of_int rl))
	| OGetFunction (r,f) -> Printf.sprintf "getfunction %d, f%d" r f
	| OClosure (r,f,v) -> Printf.sprintf "closure %d, f%d(%d)" r f v
	| OGetGlobal (r,g) -> Printf.sprintf "global %d, %d" r g
	| OSetGlobal (g,r) -> Printf.sprintf "setglobal %d, %d" g r
	| ORet r -> Printf.sprintf "ret %d" r
	| OJTrue (r,d) -> Printf.sprintf "jtrue %d,%d" r d
	| OJFalse (r,d) -> Printf.sprintf "jfalse %d,%d" r d
	| OJNull (r,d) -> Printf.sprintf "jnull %d,%d" r d
	| OJNotNull (r,d) -> Printf.sprintf "jnotnull %d,%d" r d
	| OJSLt (a,b,i) -> Printf.sprintf "jslt %d,%d,%d" a b i
	| OJSGte (a,b,i) -> Printf.sprintf "jsgte %d,%d,%d" a b i
	| OJSGt (r,a,b) -> Printf.sprintf "jsgt %d,%d,%d" r a b
	| OJSLte (r,a,b) -> Printf.sprintf "jslte %d,%d,%d" r a b
	| OJULt (a,b,i) -> Printf.sprintf "jult %d,%d,%d" a b i
	| OJUGte (a,b,i) -> Printf.sprintf "jugte %d,%d,%d" a b i
	| OJEq (a,b,i) -> Printf.sprintf "jeq %d,%d,%d" a b i
	| OJNotEq (a,b,i) -> Printf.sprintf "jnoteq %d,%d,%d" a b i
	| OJAlways d -> Printf.sprintf "jalways %d" d
	| OToDyn (r,a) -> Printf.sprintf "todyn %d,%d" r a
	| OToSFloat (r,a) -> Printf.sprintf "tosfloat %d,%d" r a
	| OToUFloat (r,a) -> Printf.sprintf "toufloat %d,%d" r a
	| OToInt (r,a) -> Printf.sprintf "toint %d,%d" r a
	| OLabel _ -> "label"
	| ONew r -> Printf.sprintf "new %d" r
	| OField (r,o,i) -> Printf.sprintf "field %d,%d[%d]" r o i
	| OMethod (r,o,m) -> Printf.sprintf "method %d,%d[%d]" r o m
	| OSetField (o,i,r) -> Printf.sprintf "setfield %d[%d],%d" o i r
	| OGetThis (r,i) -> Printf.sprintf "getthis %d,[%d]" r i
	| OSetThis (i,r) -> Printf.sprintf "setthis [%d],%d" i r
	| OThrow r -> Printf.sprintf "throw %d" r
	| ORethrow r -> Printf.sprintf "rethrow %d" r
	| OGetI8 (r,b,p) -> Printf.sprintf "geti8 %d,%d[%d]" r b p
	| OGetI32 (r,b,p) -> Printf.sprintf "geti32 %d,%d[%d]" r b p
	| OGetF32 (r,b,p) -> Printf.sprintf "getf32 %d,%d[%d]" r b p
	| OGetF64 (r,b,p) -> Printf.sprintf "getf64 %d,%d[%d]" r b p
	| OGetArray (r,a,i) -> Printf.sprintf "getarray %d,%d[%d]" r a i
	| OSetI8 (r,p,v) -> Printf.sprintf "seti8 %d,%d,%d" r p v
	| OSetI32 (r,p,v) -> Printf.sprintf "seti32 %d,%d,%d" r p v
	| OSetF32 (r,p,v) -> Printf.sprintf "setf32 %d,%d,%d" r p v
	| OSetF64 (r,p,v) -> Printf.sprintf "setf64 %d,%d,%d" r p v
	| OSetArray (a,i,v) -> Printf.sprintf "setarray %d[%d],%d" a i v
	| OSafeCast (r,v) -> Printf.sprintf "safecast %d,%d" r v
	| OUnsafeCast (r,v) -> Printf.sprintf "unsafecast %d,%d" r v
	| OArraySize (r,a) -> Printf.sprintf "arraysize %d,%d" r a
	| OError s -> Printf.sprintf "error @%d" s
	| OType (r,t) -> Printf.sprintf "type %d,%s" r (tstr t)
	| OGetType (r,v) -> Printf.sprintf "gettype %d,%d" r v
	| OGetTID (r,v) -> Printf.sprintf "gettid %d,%d" r v
	| ORef (r,v) -> Printf.sprintf "ref %d,&%d" r v
	| OUnref (v,r) -> Printf.sprintf "unref %d,*%d" v r
	| OSetref (r,v) -> Printf.sprintf "setref *%d,%d" r v
	| OToVirtual (r,v) -> Printf.sprintf "tovirtual %d,%d" r v
	| OUnVirtual (r,v) -> Printf.sprintf "unvirtual %d,%d" r v
	| ODynGet (r,o,f) -> Printf.sprintf "dynget %d,%d[@%d]" r o f
	| ODynSet (o,f,v) -> Printf.sprintf "dynset %d[@%d],%d" o f v
	| OMakeEnum (r,e,pl) -> Printf.sprintf "makeenum %d, %d(%s)" r e (String.concat "," (List.map string_of_int pl))
	| OEnumAlloc (r,e) -> Printf.sprintf "enumalloc %d, %d" r e
	| OEnumIndex (r,e) -> Printf.sprintf "enumindex %d, %d" r e
	| OEnumField (r,e,i,n) -> Printf.sprintf "enumfield %d, %d[%d:%d]" r e i n
	| OSetEnumField (e,i,r) -> Printf.sprintf "setenumfield %d[%d], %d" e i r
	| OSwitch (r,idx) -> Printf.sprintf "switch %d [%s]" r (String.concat "," (Array.to_list (Array.map string_of_int idx)))
	| ONullCheck r -> Printf.sprintf "nullcheck %d" r
	| OTrap (r,i) -> Printf.sprintf "trap %d, %d" r i
	| OEndTrap _ -> "endtrap"
	| ODump r -> Printf.sprintf "dump %d" r

let dump code =
	let lines = ref [] in
	let pr s =
		lines := s :: !lines
	in
	let all_protos = Hashtbl.create 0 in
	let tstr t =
		(match t with
		| HObj p -> Hashtbl.replace all_protos p.pname p
		| _ -> ());
		tstr t
	in
	let str idx =
		try
			code.strings.(idx)
		with _ ->
			"INVALID:" ^ string_of_int idx
	in
	let debug_infos (fid,line) =
		(try code.debugfiles.(fid) with _ -> "???") ^ ":" ^ string_of_int line
	in
	pr ("hl v" ^ string_of_int code.version);
	pr ("entry @" ^ string_of_int code.entrypoint);
	pr (string_of_int (Array.length code.strings) ^ " strings");
	Array.iteri (fun i s ->
		pr ("	@" ^ string_of_int i ^ " : " ^ String.escaped s);
	) code.strings;
	pr (string_of_int (Array.length code.ints) ^ " ints");
	Array.iteri (fun i v ->
		pr ("	@" ^ string_of_int i ^ " : " ^ Int32.to_string v);
	) code.ints;
	pr (string_of_int (Array.length code.floats) ^ " floats");
	Array.iteri (fun i f ->
		pr ("	@" ^ string_of_int i ^ " : " ^ float_repres f);
	) code.floats;
	pr (string_of_int (Array.length code.globals) ^ " globals");
	Array.iteri (fun i g ->
		pr ("	@" ^ string_of_int i ^ " : " ^ tstr g);
	) code.globals;
	pr (string_of_int (Array.length code.natives) ^ " natives");
	Array.iter (fun (lib,name,t,fidx) ->
		pr ("	@" ^ string_of_int fidx ^ " native " ^ str lib ^ "@" ^ str name ^ " " ^ tstr t);
	) code.natives;
	pr (string_of_int (Array.length code.functions) ^ " functions");
	Array.iter (fun f ->
		pr (Printf.sprintf "	fun@%d(%Xh) %s" f.findex f.findex (tstr f.ftype));
		pr (Printf.sprintf "	; %s" (debug_infos f.debug.(0)));
		Array.iteri (fun i r ->
			pr ("		r" ^ string_of_int i ^ " " ^ tstr r);
		) f.regs;
		Array.iteri (fun i o ->
			pr (Printf.sprintf "		.%-5d @%d %s" (snd f.debug.(i)) i (ostr o))
		) f.code;
	) code.functions;
	let protos = Hashtbl.fold (fun _ p acc -> p :: acc) all_protos [] in
	pr (string_of_int (List.length protos) ^ " objects protos");
	List.iter (fun p ->
		pr ("	" ^ p.pname ^ " " ^ (match p.pclassglobal with None -> "no global" | Some i -> "@" ^ string_of_int i));
		(match p.psuper with
		| None -> ()
		| Some p -> pr ("		extends " ^ p.pname));
		pr ("		" ^ string_of_int (Array.length p.pfields) ^ " fields");
		Array.iteri (fun i (_,id,t) ->
			pr ("		  @" ^ string_of_int i ^ " " ^ str id ^ " " ^ tstr t)
		) p.pfields;
		pr ("		" ^ string_of_int (Array.length p.pproto) ^ " methods");
		Array.iteri (fun i f ->
			pr ("		  @" ^ string_of_int i ^ " " ^ str f.fid ^ " fun@" ^ string_of_int f.fmethod ^ (match f.fvirtual with None -> "" | Some p -> "[" ^ string_of_int p ^ "]"))
		) p.pproto;
	) protos;
	String.concat "\n" (List.rev !lines)


(* --------------------------------------------------------------------------------------------------------------------- *)
(* HLC *)

let c_kwds = [
"auto";"break";"case";"char";"const";"continue";"default";"do";"double";"else";"enum";"extern";"float";"for";"goto";
"if";"int";"long";"register";"return";"short";"signed";"sizeof";"static";"struct";"switch";"typedef";"union";"unsigned";
"void";"volatile";"while";
(* MS specific *)
"__asm";"dllimport2";"__int8";"naked2";"__based1";"__except";"__int16";"__stdcall";"__cdecl";"__fastcall";"__int32";
"thread2";"__declspec";"__finally";"__int64";"__try";"dllexport2";"__inline";"__leave";
(* reserved by HLC *)
"t"
]

let write_c version ch (code:code) =
	let tabs = ref "" in
	let block() = tabs := !tabs ^ "\t" in
	let unblock() = tabs := String.sub (!tabs) 0 (String.length (!tabs) - 1) in
	let line str = IO.write_line ch (!tabs ^ str) in
	let expr str = line (str ^ ";") in
	let sexpr fmt = Printf.ksprintf expr fmt in
	let sprintf = Printf.sprintf in

	let keywords =
		let h = Hashtbl.create 0 in
		List.iter (fun i -> Hashtbl.add h i ()) c_kwds;
		h
	in

	let ident i = if Hashtbl.mem keywords i then "_" ^ i else i in

	let tname str = String.concat "__" (ExtString.String.nsplit str ".") in

	let rec ctype t =
		match t with
		| HVoid -> "void"
		| HI8 -> "char"
		| HI16 -> "short"
		| HI32 -> "int"
		| HF32 -> "float"
		| HF64 -> "double"
		| HBool -> "bool"
		| HBytes -> "vbytes*"
		| HDyn -> "vdynamic*"
		| HFun _ -> "vclosure*"
		| HObj p -> tname p.pname
		| HArray -> "varray*"
		| HType -> "hl_type*"
		| HRef t -> ctype t ^ "*"
		| HVirtual _ -> "vvirtual*"
		| HDynObj -> "vdynobj*"
		| HAbstract (name,_) -> name ^ "*"
		| HEnum _ -> "venum*"
		| HNull _ -> "vdynamic*"
	in

	let is_gc_ptr = function
		| HVoid | HI8 | HI16 | HI32 | HF32 | HF64 | HBool | HType | HRef _ -> false
		| HBytes | HDyn | HFun _ | HObj _ | HArray | HVirtual _ | HDynObj | HAbstract _ | HEnum _ | HNull _ -> true
	in

	let type_id t =
		match t with
		| HVoid -> "HVOID"
		| HI8 -> "HI8"
		| HI16 -> "HI16"
		| HI32 -> "HI32"
		| HF32 -> "HF32"
		| HF64 -> "HF64"
		| HBool -> "HBOOL"
		| HBytes -> "HBYTES"
		| HDyn -> "HDYN"
		| HFun _ -> "HFUN"
		| HObj _ -> "HOBJ"
		| HArray -> "HARRAY"
		| HType -> "HTYPE"
		| HRef _ -> "HREF"
		| HVirtual _ -> "HVIRTUAL"
		| HDynObj -> "HDYNOBJ"
		| HAbstract _ -> "HABSTRACT"
		| HEnum _ -> "HENUM"
		| HNull _ -> "HNULL"
	in

	let var_type n t =
		ctype t ^ " " ^ ident n
	in

	let version_major = version / 1000 in
	let version_minor = (version mod 1000) / 100 in
	let version_revision = (version mod 100) in
	let ver_str = Printf.sprintf "%d.%d.%d" version_major version_minor version_revision in
	line ("// Generated by HLC " ^ ver_str ^ " (HL v" ^ string_of_int code.version ^")");
	line "#include <hlc.h>";
	let types = gather_types code in
	let tfuns = Array.create (Array.length code.functions + Array.length code.natives) ([],HVoid) in

	let enum_type t index =
		let eindex = lookup types t (fun() -> assert false) in
		"enum$" ^ string_of_int eindex ^ "_" ^ string_of_int index
	in

	line "";
	line "// Types definitions";
	DynArray.iter (fun t ->
		match t with
		| HObj o ->
			let name = tname o.pname in
			expr ("typedef struct _" ^ name ^ " *" ^ name);
		| HAbstract (name,_) ->
			expr ("typedef struct _" ^ name ^ " "  ^ name);
		| _ ->
			()
	) types.arr;

	line "";
	line "// Types implementation";
	DynArray.iter (fun t ->
		match t with
		| HObj o ->
			let name = tname o.pname in
			line ("struct _" ^ name ^ " {");
			block();
			(match o.psuper with
			| None ->
				expr ("hl_type *$type");
			| Some c ->
				expr ("struct _" ^ tname c.pname));
			Array.iter (fun (n,_,t) ->
				expr (var_type n t)
			) o.pfields;
			unblock();
			expr "}";
		| HEnum e ->
			Array.iteri (fun i (_,_,pl) ->
				line ("typedef struct {");
				block();
				expr "struct _venum";
				Array.iteri (fun i t ->
					expr (var_type ("p" ^ string_of_int i) t)
				) pl;
				unblock();
				sexpr "} %s" (enum_type t i);
			) e.efields
		| _ ->
			()
	) types.arr;

	line "";
	line "// Types values declaration";
	DynArray.iteri (fun i t ->
		sexpr "static hl_type type$%d = { %s } /* %s */" i (type_id t) (tstr t);
		match t with
		| HObj o ->
			line (Printf.sprintf "#define %s__val &type$%d" (tname o.pname) i)
		| _ ->
			()
	) types.arr;

	line "";
	line "// Globals";
	Array.iteri (fun i t ->
		let name = "global$" ^ string_of_int i in
		sexpr "static %s = 0" (var_type name t)
	) code.globals;

	line "";
	line "// Natives functions";
	Array.iter (fun (lib,name,t,idx) ->
		match t with
		| HFun (args,t) ->
			let fname =
				let lib = code.strings.(lib) in
				let lib = if lib = "std" then "hl" else lib in
				lib ^ "_" ^ code.strings.(name)
			in
			sexpr "%s %s(%s)" (ctype t) fname (String.concat "," (List.map ctype args));
			line (Printf.sprintf "#define fun$%d %s" idx fname);
			Array.set tfuns idx (args,t)
		| _ ->
			assert false
	) code.natives;

	line "";
	line "// Functions declaration";
	Array.iter (fun f ->
		match f.ftype with
		| HFun (args,t) ->
			sexpr "%s fun$%d(%s)" (ctype t) f.findex (String.concat "," (List.map ctype args));
			Array.set tfuns f.findex (args,t)
		| _ ->
			assert false
	) code.functions;

	line "";
	line "// Strings";
	Array.iteri (fun i str ->
		let s = utf8_to_utf16 str in
		let rec loop i =
			if i = String.length s then [] else
			let c = String.get s i in
			string_of_int (int_of_char c) :: loop (i+1)
		in
		sexpr "static vbytes string$%d[] = {%s} /* %s */" i (String.concat "," (loop 0)) str
	) code.strings;

	let type_value t =
		let index = lookup types t (fun() -> assert false) in
		"&type$" ^ string_of_int index
	in

	line "";
	line "// Types values data";
	DynArray.iteri (fun i t ->
		match t with
		| HObj o ->
			let field_value (name,name_id,t) =
				sprintf "{(const uchar*)string$%d, %s, %ld}" name_id (type_value t) (hash name)
			in
			let proto_value p =
				sprintf "{(const uchar*)string$%d, %d, %d, %ld}" p.fid p.fmethod (match p.fvirtual with None -> -1 | Some i -> i) (hash p.fname)
			in
			let fields =
				if Array.length o.pfields = 0 then "NULL" else
				let name = sprintf "fields$%d" i in
				sexpr "static hl_obj_field %s[] = {%s}" name (String.concat "," (List.map field_value (Array.to_list o.pfields)));
				name
			in
			let proto =
				if Array.length o.pproto = 0 then "NULL" else
				let name = sprintf "proto$%d" i in
				sexpr "static hl_obj_proto %s[] = {%s}" name (String.concat "," (List.map proto_value (Array.to_list o.pproto)));
				name
			in
			let ofields = [
				string_of_int (Array.length o.pfields);
				string_of_int (Array.length o.pproto);
				sprintf "(const uchar*)string$%d" o.pid;
				(match o.psuper with None -> "NULL" | Some c -> sprintf "%s__val" (tname c.pname));
				fields;
				proto
			] in
			sexpr "static hl_type_obj obj$%d = {%s}" i (String.concat "," ofields);
		| HEnum e ->
			let constr_name = sprintf "econstructs$%d" i in
			let constr_value cid (_,nid,tl) =
				let tval = if Array.length tl = 0 then "NULL" else
					let name = sprintf "econstruct$%d_%d" i cid in
					sexpr "static hl_type *%s[] = {%s}" name (String.concat "," (List.map type_value (Array.to_list tl)));
					name
				in
				sprintf "{(const uchar*)string$%d, %d, %s}" nid (Array.length tl) tval
			in
			sexpr "static hl_enum_construct %s[] = {%s}" constr_name (String.concat "," (Array.to_list (Array.mapi constr_value e.efields)));
			let efields = [
				if e.eid = 0 then "NULL" else sprintf "(const uchar*)string$%d" e.eid;
				string_of_int (Array.length e.efields);
				constr_name
			] in
			sexpr "static hl_type_enum enum$%d = {%s}" i (String.concat "," efields);
		| _ ->
			()
	) types.arr;


	line "";
	line "// Entry point";
	line "void hl_entry_point() {";
	block();
	let rec loop i =
		if i = Array.length code.functions + Array.length code.natives then [] else
		("fun$" ^ string_of_int i) :: loop (i + 1)
	in
	sexpr "static void *functions_ptrs[] = {%s}" (String.concat "," (loop 0));
	let rec loop i =
		if i = Array.length code.functions + Array.length code.natives then [] else
		let args, t = tfuns.(i) in
		(type_value (HFun (args,t))) :: loop (i + 1)
	in
	sexpr "static hl_type *functions_types[] = {%s}" (String.concat "," (loop 0));
	expr "hl_module_context ctx";
	expr "hl_alloc_init(&ctx.alloc)";
	expr "ctx.functions_ptrs = functions_ptrs";
	expr "ctx.functions_types = functions_types";
	DynArray.iteri (fun i t ->
		match t with
		| HObj o ->
			sexpr "obj$%d.m = &ctx" i;
			sexpr "type$%d.obj = &obj$%d" i i;
		| HEnum _ ->
			sexpr "type$%d.tenum = &enum$%d" i i;
		| _ ->
			()
	) types.arr;
	sexpr "fun$%d()" code.entrypoint;
	unblock();
	line "}";

	line "";
	line "// Static data";
	Array.iter (fun f ->
		Array.iteri (fun i op ->
			match op with
			| OGetFunction (_,fid) ->
				let args, t = tfuns.(fid) in
				sexpr "static vclosure cl$%d = { %s, fun$%d, 0 }" fid (type_value (HFun (args,t))) fid;
			| _ ->
				()
		) f.code
	) code.functions;

	line "";
	line "// Functions code";
	Array.iter (fun f ->
		let rid = ref (-1) in
		let reg id = "r" ^ string_of_int id in

		let label id = "label$" ^ string_of_int f.findex ^ "$" ^ string_of_int id in

		let rtype r = f.regs.(r) in

		let rcast r t =
			if tsame (rtype r) t then (reg r)
			else if not (safe_cast (rtype r) t) then assert false
			else Printf.sprintf "((%s)%s)" (ctype t) (reg r)
		in

		let rassign r t =
			let rt = rtype r in
			if t = HVoid then "" else
			let assign = reg r ^ " = " in
			if tsame t rt then assign else
			if not (safe_cast t rt) then assert false
			else assign ^ "(" ^ ctype rt ^ ")"
		in

		let ocall r fid args =
			let targs, rt = tfuns.(fid) in
			let rstr = rassign r rt in
			sexpr "%sfun$%d(%s)" rstr fid (String.concat "," (List.map2 rcast args targs))
		in

		let set_field obj fid v =
			match rtype obj with
			| HObj o ->
				let name, t = resolve_field o fid in
				sexpr "%s->%s = %s" (reg obj) (ident name) (rcast v t)
			| HVirtual v ->
				sexpr "hl_fatal(\"%s\")" "SETFIELD-VIRTUAL"
			| _ ->
				assert false
		in

		let get_field r obj fid =
			match rtype obj with
			| HObj o ->
				let name, t = resolve_field o fid in
				sexpr "%s%s->%s" (rassign r t) (reg obj) (ident name)
			| HVirtual v ->
				sexpr "hl_fatal(\"%s\")" "GETFIELD-VIRTUAL"
			| _ ->
				assert false
		in

		let fret = (match f.ftype with
		| HFun (args,t) ->
			line (Printf.sprintf "static %s fun$%d(%s) {" (ctype t) f.findex (String.concat "," (List.map (fun t -> incr rid; var_type (reg !rid) t) args)));
			t
		| _ ->
			assert false
		) in
		block();
		Array.iteri (fun i t ->
			if i <= !rid || t = HVoid then ()
			else
			expr (var_type (reg i) t);
		) f.regs;
		let flabels = Array.make (Array.length f.code) false in

		Array.iteri (fun i op ->
			if flabels.(i) then line (label i ^":");
			let label delta =
				let addr = delta + i + 1 in
				flabels.(addr) <- true;
				label addr
			in
			match op with
			| OMov (r,v) ->
				if rtype r <> HVoid then sexpr "%s = %s" (reg r) (rcast v (rtype r))
			| OInt (r,idx) ->
				sexpr "%s = %ld" (reg r) code.ints.(idx)
			| OFloat (r,idx) ->
				sexpr "%s = %f" (reg r) code.floats.(idx)
			| OBool (r,b) ->
				sexpr "%s = %s" (reg r) (if b then "true" else "false")
			| OBytes (r,idx) ->
				sexpr "%s = string$%d" (reg r) idx
			| OString (r,idx) ->
				sexpr "%s = string$%d" (reg r) idx
			| ONull r ->
				sexpr "%s = NULL" (reg r)
			| OAdd (r,a,b) ->
				sexpr "%s = %s + %s" (reg r) (reg a) (reg b)
			| OSub (r,a,b) ->
				sexpr "%s = %s - %s" (reg r) (reg a) (reg b)
			| OMul (r,a,b) ->
				sexpr "%s = %s * %s" (reg r) (reg a) (reg b)
			| OSDiv (r,a,b) ->
				(match rtype r with
				| HI8 | HI16 | HI32 ->
					sexpr "%s = %s == 0 ? 0 : %s / %s" (reg r) (reg b) (reg a) (reg b)
				| _ ->
					sexpr "%s = %s / %s" (reg r) (reg a) (reg b))
			| OUDiv (r,a,b) ->
				sexpr "%s = %s == 0 ? 0 : ((unsigned)%s) / ((unsigned)%s)" (reg r) (reg b) (reg a) (reg b)
			| OSMod (r,a,b) ->
				(match rtype r with
				| HI8 | HI16 | HI32 ->
					sexpr "%s = %s == 0 ? 0 : %s %% %s" (reg r) (reg b) (reg a) (reg b)
				| HF32 ->
					sexpr "%s = fmodf(%s,%s)" (reg r) (reg a) (reg b)
				| HF64 ->
					sexpr "%s = fmod(%s,%s)" (reg r) (reg a) (reg b)
				| _ ->
					assert false)
			| OUMod (r,a,b) ->
				sexpr "%s = %s == 0 ? 0 : ((unsigned)%s) %% ((unsigned)%s)" (reg r) (reg b) (reg a) (reg b)
			| OShl (r,a,b) ->
				sexpr "%s = %s << %s" (reg r) (reg a) (reg b)
			| OSShr (r,a,b) ->
				sexpr "%s = %s >> %s" (reg r) (reg a) (reg b)
			| OUShr (r,a,b) ->
				sexpr "%s = ((unsigned)%s) >> %s" (reg r) (reg a) (reg b)
			| OAnd (r,a,b) ->
				sexpr "%s = %s & %s" (reg r) (reg a) (reg b)
			| OOr (r,a,b) ->
				sexpr "%s = %s | %s" (reg r) (reg a) (reg b)
			| OXor (r,a,b) ->
				sexpr "%s = %s ^ %s" (reg r) (reg a) (reg b)
			| ONeg (r,v) ->
				sexpr "%s = -%s" (reg r) (reg v)
			| ONot (r,v) ->
				sexpr "%s = !%s" (reg r) (reg v)
			| OIncr r ->
				sexpr "++%s" (reg r)
			| ODecr r ->
				sexpr "--%s" (reg r)
			| OCall0 (r,fid) ->
				ocall r fid []
			| OCall1 (r,fid,a) ->
				ocall r fid [a]
			| OCall2 (r,fid,a,b) ->
				ocall r fid [a;b]
			| OCall3 (r,fid,a,b,c) ->
				ocall r fid [a;b;c]
			| OCall4 (r,fid,a,b,c,d) ->
				ocall r fid [a;b;c;d]
			| OCallN (r,fid,rl) ->
				ocall r fid rl


	(*
	| OCallMethod of reg * field index * reg list
	| OCallThis of reg * field index * reg list
	| OCallClosure of reg * reg * reg list
	*)
			| OGetFunction (r,fid) ->
				sexpr "%s = &cl$%d" (reg r) fid
	(*
	| OClosure of reg * functable index * reg (* closure *)
	*)

			| OGetGlobal (r,g) ->
				sexpr "%s = global$%d" (reg r) g
			| OSetGlobal (g,r) ->
				sexpr "global$%d = %s" g (reg r)
			| ORet r ->
				if rtype r = HVoid then expr "return" else sexpr "return %s" (rcast r fret)
			| OJTrue (r,d) | OJNotNull (r,d) ->
				sexpr "if( %s ) goto %s" (reg r) (label d)
			| OJFalse (r,d) | OJNull (r,d) ->
				sexpr "if( !%s ) goto %s" (reg r) (label d)
			| OJSLt (a,b,d) ->
				sexpr "if( %s < %s ) goto %s" (reg a) (reg b) (label d)
			| OJSGte (a,b,d) ->
				sexpr "if( %s >= %s ) goto %s" (reg a) (reg b) (label d)
			| OJSGt (a,b,d) ->
				sexpr "if( %s > %s ) goto %s" (reg a) (reg b) (label d)
			| OJSLte (a,b,d) ->
				sexpr "if( %s <= %s ) goto %s" (reg a) (reg b) (label d)
			| OJULt (a,b,d) ->
				sexpr "if( ((unsigned)%s) < ((unsigned)%s) ) goto %s" (reg a) (reg b) (label d)
			| OJUGte (a,b,d) ->
				sexpr "if( ((unsigned)%s) >= ((unsigned)%s) ) goto %s" (reg a) (reg b) (label d)
			| OJEq (a,b,d) ->
				sexpr "if( %s == %s ) goto %s" (reg a) (reg b) (label d)
			| OJNotEq (a,b,d) ->
				sexpr "if( %s != %s ) goto %s" (reg a) (reg b) (label d)
			| OJAlways d ->
				sexpr "goto %s" (label d)
			| OLabel _ ->
				if not (flabels.(i)) then line (label (-1) ^ ":")
			| OToDyn (r,v) ->
				sexpr "%s = (vdynamic*)hl_gc_alloc%s(sizeof(vdynamic))" (reg r) (if is_gc_ptr (rtype v) then "" else "_noptr");
				sexpr "%s->t = %s" (reg r) (type_value (rtype v));
				(match rtype v with
				| HI8 | HI16 | HI32 | HBool ->
					sexpr "%s->v.i = %s" (reg r) (reg v)
				| HF32 ->
					sexpr "%s->v.f = %s" (reg r) (reg v)
				| HF64 ->
					sexpr "%s->v.d = %s" (reg r) (reg v)
				| _ ->
					sexpr "%s->v.ptr = %s" (reg r) (reg v))
			| OToSFloat (r,v) ->
				sexpr "%s = %s" (reg r) (reg v)
			| OToUFloat (r,v) ->
				sexpr "%s = (unsigned)%s" (reg r) (reg v)
			| OToInt (r,v) ->
				sexpr "%s = (int)%s" (reg r) (reg v)
			| ONew r ->
				(match rtype r with
				| HObj o -> sexpr "%s = (%s)hl_alloc_obj(%s)" (reg r) (tname o.pname) (tname o.pname ^ "__val")
				| HDynObj -> sexpr "%s = hl_alloc_dynobj()" (reg r)
				| _ -> assert false)
			| OField (r,obj,fid) ->
				get_field r obj fid
	(*
	| OMethod of reg * reg * field index (* closure *)
	*)

			| OSetField (obj,fid,v) ->
				set_field obj fid v
			| OGetThis (r,fid) ->
				get_field r 0 fid
			| OSetThis (fid,r) ->
				set_field 0 fid r
	(*
	| OThrow of reg
	| ORethrow of reg
	*)
			| OGetI8 (r,b,idx) ->
				sexpr "%s = *(unsigned char*)(%s + %s)" (reg r) (reg b) (reg idx)
			| OGetI32 (r,b,idx) ->
				sexpr "%s = *(int*)(%s + %s)" (reg r) (reg b) (reg idx)
			| OGetF32 (r,b,idx) ->
				sexpr "%s = *(float*)(%s + %s)" (reg r) (reg b) (reg idx)
			| OGetF64 (r,b,idx) ->
				sexpr "%s = *(double*)(%s + %s)" (reg r) (reg b) (reg idx)
			| OGetArray (r, arr, idx) ->
				sexpr "%s = ((%s*)(%s + 1))[%s]" (reg r) (ctype (rtype r)) (reg arr) (reg idx)
			| OSetI8 (b,idx,r) ->
				sexpr "*(unsigned char*)(%s + %s) = %s" (reg b) (reg idx) (reg r)
			| OSetI32 (b,idx,r) ->
				sexpr "*(int*)(%s + %s) = %s" (reg b) (reg idx) (reg r)
			| OSetF32 (b,idx,r) ->
				sexpr "*(float*)(%s + %s) = %s" (reg b) (reg idx) (reg r)
			| OSetF64 (b,idx,r) ->
				sexpr "*(double*)(%s + %s) = %s" (reg b) (reg idx) (reg r)
			| OSetArray (arr,idx,v) ->
				sexpr "((%s*)(%s + 1))[%s] = %s" (ctype (rtype v)) (reg arr) (reg idx) (reg v)
(*
	| OSafeCast of reg * reg
	| OUnsafeCast of reg * reg
*)
			| OArraySize (r,a) ->
				sexpr "%s = %s->size" (reg r) (reg a)
(*	| OError of string index
	*)
			| OType (r,t) ->
				sexpr "%s = %s" (reg r) (type_value t)
	(*| OGetType of reg * reg
	| OGetTID of reg * reg
	*)
			| ORef (r,v) ->
				sexpr "%s = &%s" (reg r) (reg v)
			| OUnref (r,v) ->
				sexpr "%s = *%s" (reg r) (reg v)
			| OSetref (r,v) ->
				sexpr "*%s = %s" (reg r) (reg v)
			| OToVirtual (r,v) ->
				sexpr "%s = hl_to_virtual(%s,(vdynamic*)%s)" (reg r) (type_value (rtype r)) (reg v)
	(*
	| OUnVirtual of reg * reg
	| ODynGet of reg * reg * string index
	*)
			| ODynSet (o,str,v) ->
				let h = hash code.strings.(str) in
				let prefix = (match rtype v with
				| HBool | HI8 | HI16 | HI32 -> "set32"
				| HF32 -> "setf32"
				| HF64 -> "setf64"
				| _ -> "setptr"
				) in
				sexpr "hl_dyn_%s((vdynamic*)%s,%ld,%s,%s)" prefix (reg o) h (type_value (rtype v)) (reg v)
			| OMakeEnum (r,eid,rl) ->
				let et = enum_type (rtype r) eid in
				let has_ptr = List.exists (fun r -> is_gc_ptr (rtype r)) rl in
				sexpr "%s = (venum*)hl_gc_alloc%s(sizeof(%s))" (reg r) (if has_ptr then "" else "_noptr") et;
				sexpr "%s->index = %d" (reg r) eid;
				iteri (fun i v ->
					sexpr "((%s*)%s)->p%d = %s" et (reg r) i (reg v)
				) rl;

	(*| OEnumAlloc of reg * field index
	| OEnumIndex of reg * reg
	| OEnumField of reg * reg * field index * int
	| OSetEnumField of reg * int * reg
	| OSwitch of reg * int array
	*)
			| ONullCheck r ->
				sexpr "if( %s == NULL ) hl_error_msg(USTR(\"Null access\"))" (reg r)
	(*
	| OTrap of reg * int
	| OEndTrap of unused
	| ODump of reg*)
			| _ ->
				sexpr "hl_fatal(\"%s\")" (ostr op)
		) f.code;
		unblock();
		line "}";
		line "";
	) code.functions


(* --------------------------------------------------------------------------------------------------------------------- *)

let generate com =
	let get_class name =
		try
			match List.find (fun t -> (t_infos t).mt_path = (["hl";"types"],name)) com.types with
			| TClassDecl c -> c
			| _ -> assert false
		with
			Not_found ->
				failwith ("hl class " ^ name ^ " not found")
	in
	let ctx = {
		com = com;
		m = method_context 0 HVoid null_capture;
		cints = new_lookup();
		cstrings = new_lookup();
		cfloats = new_lookup();
		cglobals = new_lookup();
		cnatives = new_lookup();
		cfunctions = DynArray.create();
		overrides = Hashtbl.create 0;
		cached_types = PMap.empty;
		cfids = new_lookup();
		defined_funs = Hashtbl.create 0;
		array_impl = {
			aall = get_class "ArrayAccess";
			abase = get_class "ArrayBase";
			adyn = get_class "ArrayDyn";
			aobj = get_class "ArrayObj";
			ai32 = get_class "ArrayBasic_Int";
			af64 = get_class "ArrayBasic_Float";
		};
		base_class = get_class "Class";
		base_enum = get_class "Enum";
		base_type = get_class "BaseType";
		core_type = get_class "CoreType";
		core_enum = get_class "CoreEnum";
		anons_cache = [];
		rec_cache = [];
		method_wrappers = PMap.empty;
		cdebug_files = new_lookup();
	} in
	let all_classes = Hashtbl.create 0 in
	List.iter (fun t ->
		match t with
		| TClassDecl ({ cl_path = ["hl";"types"], ("BasicIterator"|"ArrayBasic") } as c) ->
			c.cl_extern <- true
		| TClassDecl c ->
			let rec loop p f =
				match p with
				| Some (p,_) when PMap.mem f.cf_name p.cl_fields || loop p.cl_super f ->
					Hashtbl.replace ctx.overrides (f.cf_name,p.cl_path) true;
					true
				| _ ->
					false
			in
			List.iter (fun f -> ignore(loop c.cl_super f)) c.cl_overrides;
			Hashtbl.add all_classes c.cl_path c
 		| _ -> ()
	) com.types;
	ignore(alloc_string ctx "");
	ignore(class_type ctx ctx.base_class [] false);
	List.iter (generate_type ctx) com.types;
	let ep = generate_static_init ctx in
	let code = {
		version = 1;
		entrypoint = ep;
		strings = DynArray.to_array ctx.cstrings.arr;
		ints = DynArray.to_array ctx.cints.arr;
		floats = DynArray.to_array ctx.cfloats.arr;
		globals = DynArray.to_array ctx.cglobals.arr;
		natives = DynArray.to_array ctx.cnatives.arr;
		functions = DynArray.to_array ctx.cfunctions;
		debugfiles = DynArray.to_array ctx.cdebug_files.arr;
	} in
	Array.sort (fun (lib1,_,_,_) (lib2,_,_,_) -> lib1 - lib2) code.natives;
	if Common.defined com Define.Dump then Std.output_file "dump/hlcode.txt" (dump code);
	PMap.iter (fun (s,p) fid ->
		if not (Hashtbl.mem ctx.defined_funs fid) then failwith (Printf.sprintf "Unresolved method %s:%s(@%d)" (s_type_path p) s fid)
	) ctx.cfids.map;
	check code;
	let ch = IO.output_string() in
	if file_extension com.file = "c" then write_c com.Common.version ch code else write_code ch code;
	let str = IO.close_out ch in
	let ch = open_out_bin com.file in
	output_string ch str;
	close_out ch;
	if Common.defined com Define.Interp then ignore(interp code)

