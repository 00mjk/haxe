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
open Ast
open Type
open Common

type reg = int
type global = int
type 'a index = int
type functable

type ttype =
	| TVoid
	| TUI8
	| TI32
	| TF32
	| TF64
	| TBool
	| TAny
	| TFun of ttype list * ttype
	| TObj of class_proto

and class_proto = {
	pname : string;
	pid : int;
	mutable psuper : class_proto option;
	mutable pproto : (string * string index * functable index) array;
	mutable pfields : (string * string index * ttype) array;
	mutable pindex : (string, int) PMap.t;
}

type unused = int
type field

type opcode =
	| OMov of reg * reg
	| OInt of reg * int index
	| OFloat of reg * float index
	| OBool of reg * bool
	| OAdd of reg * reg * reg
	| OSub of reg * reg * reg
	| OMul of reg * reg * reg
	| ODiv of reg * reg * reg
	| OIncr of reg
	| ODecr of reg
	| OCall0 of reg * functable index
	| OCall1 of reg * functable index * reg
	| OCall2 of reg * functable index * reg * reg
	| OCall3 of reg * functable index * reg * reg * reg
	| OCall4 of reg * functable index * reg * reg * reg * reg
	| OCallN of reg * functable index * reg list
	| OCallMethod of reg * field index * reg list
	| OCallClosure of reg * reg * reg list
	| OGetFunction of reg * functable index (* closure *)
	| OClosure of reg * functable index * reg (* closure *)
	| OGetGlobal of reg * global
	| OSetGlobal of reg * global
	| OEq of reg * reg * reg
	| ONotEq of reg * reg * reg
	| OLt of reg * reg * reg
	| OGte of reg * reg * reg
	| ORet of reg
	| OJTrue of reg * int
	| OJFalse of reg * int
	| OJNull of reg * int
	| OJNotNull of reg * int
	| OJLt of reg * reg * int
	| OJGte of reg * reg * int
	| OJEq of reg * reg * int
	| OJNeq of reg * reg * int
	| OJAlways of int
	| OToAny of reg * reg
	| OLabel of unused
	| ONew of reg
	| OField of reg * reg * field index
	| OMethod of reg * reg * field index (* closure *)
	| OSetField of reg * field index * reg
	| OGetThis of reg * field index
	| OSetThis of field index * reg

type fundecl = {
	findex : functable index;
	ftype : ttype;
	regs : ttype array;
	code : opcode array;
}

type code = {
	version : int;
	entrypoint : global;
	strings : string array;
	ints : int32 array;
	floats : float array;
	(* types : ttype array // only in bytecode, rebuilt on save() *)
	globals : ttype array;
	natives : (string index * ttype * functable index) array;
	functions : fundecl array;
}

(* compiler *)

type ('a,'b) lookup = {
	arr : 'b DynArray.t;
	mutable map : ('a, int) PMap.t;
}

type method_context = {
	mregs : (int, ttype) lookup;
	mops : opcode DynArray.t;
}

type context = {
	com : Common.context;
	cglobals : (string, ttype) lookup;
	cstrings : (string, string) lookup;
	cfloats : (float, float) lookup;
	cints : (int32, int32) lookup;
	cnatives : (string, (string index * ttype * functable index)) lookup;
	cfids : (string * path, unit) lookup;
	cfunctions : fundecl DynArray.t;
	overrides : (string * path, bool) Hashtbl.t;
	mutable cached_types : (path, ttype) PMap.t;
	mutable m : method_context;
}

(* --- *)

type access =
	| ANone
	| AGlobal of global
	| ALocal of reg
	| AStaticFun of fundecl index
	| AInstanceFun of texpr * fundecl index
	| AInstanceProto of texpr * field index
	| AInstanceField of texpr * field index

let rec tstr ?(detailed=false) t =
	match t with
	| TVoid -> "void"
	| TUI8 -> "ui8"
	| TI32 -> "i32"
	| TF32 -> "f32"
	| TF64 -> "f64"
	| TBool -> "bool"
	| TAny -> "any"
	| TFun (args,ret) -> "(" ^ String.concat "," (List.map (tstr ~detailed) args) ^ "):" ^ tstr ~detailed ret
	| TObj o when not detailed -> "#" ^ o.pname
	| TObj o ->
		let fields = "{" ^ String.concat "," (List.map (fun(s,_,t) -> s ^ " : " ^ tstr ~detailed:false t) (Array.to_list o.pfields)) ^ "}" in
		let proto = "{"  ^ String.concat "," (List.map (fun(s,_,g) -> s ^ "@" ^  string_of_int g) (Array.to_list o.pproto)) ^ "}" in
		"#" ^ o.pname ^ "[" ^ (match o.psuper with None -> "" | Some p -> ">" ^ p.pname ^ " ") ^ "fields=" ^ fields ^ " proto=" ^ proto ^ "]"

let iteri f l =
	let p = ref (-1) in
	List.iter (fun v -> incr p; f !p v) l

let new_lookup() =
	{
		arr = DynArray.create();
		map = PMap.empty;
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

let method_context() =
	{
		mregs = new_lookup();
		mops = DynArray.create();
	}

let field_name c f =
	s_type_path c.cl_path ^ ":" ^ f.cf_name

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

let member_fun c t =
	match follow t with
	| Type.TFun (args, ret) -> Type.TFun (("this",false,TInst(c,[])) :: args, ret)
	| _ -> assert false

let rec to_type ctx t =
	match t with
	| TMono r ->
		(match !r with
		| None -> TAny
		| Some t -> to_type ctx t)
	| TType (t,tl) ->
		to_type ctx (apply_params t.t_params tl t.t_type)
	| TLazy f ->
		to_type ctx (!f())
	| Type.TFun (args, ret) ->
		TFun (List.map (fun (_,_,t) -> to_type ctx t) args, to_type ctx ret)
	| TAnon _ ->
		TAny
	| TDynamic _ ->
		TAny
	| TEnum (e,_) ->
		assert false
	| TInst (c,_) ->
		class_type ctx c
	| TAbstract (a,pl) ->
		if Meta.has Meta.CoreType a.a_meta then
			(match a.a_path with
			| [], "Void" -> TVoid
			| [], "Int" -> TI32
			| [], "Float" -> TF64
			| _ -> failwith ("Unknown core type " ^ s_type_path a.a_path))
		else
			to_type ctx (Abstract.get_underlying_type a pl)

and class_type ctx c =
	try
		PMap.find c.cl_path ctx.cached_types
	with Not_found ->
		let pname = s_type_path c.cl_path in
		let p = {
			pname = pname;
			pid = alloc_string ctx pname;
			psuper = None;
			pproto = [||];
			pfields = [||];
			pindex = PMap.empty;
		} in
		let t = TObj p in
		ctx.cached_types <- PMap.add c.cl_path t ctx.cached_types;
		(match c.cl_super with
		| None -> ()
		| Some (c,_) ->
			(match class_type ctx c with
			| TObj psup -> p.psuper <- Some psup
			| _ -> assert false));
		let fa = DynArray.create() and pa = DynArray.create() in
		List.iter (fun f ->
			if is_extern_field f then () else
			match f.cf_kind with
			| Var _ | Method MethDynamic ->
				let t = to_type ctx f.cf_type in
				p.pindex <- PMap.add f.cf_name (DynArray.length fa) p.pindex;
				DynArray.add fa (f.cf_name, alloc_string ctx f.cf_name, t);
			| Method _ when is_overriden ctx c f ->
				let g = alloc_fid ctx c f in
				p.pindex <- PMap.add f.cf_name (DynArray.length pa) p.pindex;
				(* can't use global_type here *)
				DynArray.add pa (f.cf_name, alloc_string ctx f.cf_name, g)
			| _ -> ()
		) c.cl_ordered_fields;
		p.pfields <- DynArray.to_array fa;
		p.pproto <- DynArray.to_array pa;
		t

and alloc_fid ctx c f =
	match f.cf_kind with
	| Var _ | Method MethDynamic -> assert false
	| _ -> lookup ctx.cfids (f.cf_name, c.cl_path) (fun() -> ())

and alloc_function_name ctx f =
	lookup ctx.cfids (f, ([],"")) (fun() -> ())

let alloc_global ctx name t =
	lookup ctx.cglobals name (fun() -> to_type ctx t)

let alloc_reg ctx v =
	if v.v_capture then assert false;
	lookup ctx.m.mregs v.v_id (fun() -> to_type ctx v.v_type)

let alloc_tmp ctx t =
	let rid = DynArray.length ctx.m.mregs.arr in
	DynArray.add ctx.m.mregs.arr t;
	rid

let op ctx o =
	DynArray.add ctx.m.mops o

let jump ctx f =
	let pos = DynArray.length ctx.m.mops in
	DynArray.add ctx.m.mops (OJAlways (-1)); (* loop *)
	(fun() -> DynArray.set ctx.m.mops pos (f (DynArray.length ctx.m.mops - pos - 1)))

let rtype ctx r =
	DynArray.get ctx.m.mregs.arr r

let rec resolve_field ctx p fname proto =
	(* each class contains only its own fields, so let's get absolute index *)
	let rec loop id sup =
		match sup with
		| None -> id
		| Some p -> loop (id + (if proto then Array.length p.pproto else Array.length p.pfields)) p.psuper
	in
	try
		let fid = PMap.find fname p.pindex in
		loop fid p.psuper
	with Not_found ->
		match p.psuper with
		| None -> assert false
		| Some p -> resolve_field ctx p fname proto

let rec eval_to ctx e (t:ttype) =
	let r = eval_expr ctx e in
	cast_to ctx r t

and cast_to ctx (r:reg) (t:ttype) =
	let rt = rtype ctx r in
	if t = rt then r else
	match rt, t with
	| _ , TAny ->
		let tmp = alloc_tmp ctx TAny in
		op ctx (OToAny (tmp, r));
		tmp
	| _ ->
		failwith ("Don't know how to cast " ^ tstr rt ^ " to " ^ tstr t)

and get_access ctx e =
	match e.eexpr with
	| TField (ethis, a) ->
		(match a, follow ethis.etype with
		| FStatic (c,({ cf_kind = Var _ | Method MethDynamic } as f)), _ ->
			AGlobal (alloc_global ctx (field_name c f) f.cf_type)
		| FStatic (c,({ cf_kind = Method _ } as f)), _ ->
			AStaticFun (alloc_fid ctx c f)
		| FClosure (Some (cdef,_), ({ cf_kind = Method m } as f)), TInst (c,_)
		| FInstance (cdef,_,({ cf_kind = Method m } as f)), TInst (c,_) when m <> MethDynamic ->
			if not (is_overriden ctx c f) then
				AInstanceFun (ethis, alloc_fid ctx cdef f)
			else (match class_type ctx cdef with
			| TObj p -> AInstanceProto (ethis, resolve_field ctx p f.cf_name true)
			| _ -> assert false)
		| FInstance (cdef,_,f), _ | FClosure (Some (cdef,_), f), _ ->
			(match class_type ctx cdef with
			| TObj p -> AInstanceField (ethis, resolve_field ctx p f.cf_name false)
			| _ -> assert false)
		| _ ->
			ANone)
	| TLocal v ->
		ALocal (alloc_reg ctx v)
	| TParenthesis e ->
		get_access ctx e
	| _ ->
		ANone

and jump_expr ctx e jcond =
	match e.eexpr with
	| TParenthesis e ->
		jump_expr ctx e jcond
	| TBinop (OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte as op, e1, e2) ->
		let r1 = eval_expr ctx e1 in
		let r2 = eval_expr ctx e2 in
		jump ctx (fun i ->
			match op with
			| OpEq -> if jcond then OJEq (r1,r2,i) else OJNeq (r1,r2,i)
			| OpNotEq -> if jcond then OJNeq (r1,r2,i) else OJEq (r1,r2,i)
			| OpGt -> if jcond then OJLt (r2,r1,i) else OJGte (r2,r1,i)
			| OpGte -> if jcond then OJGte (r1,r2,i) else OJLt (r1,r2,i)
			| OpLt -> if jcond then OJLt (r1,r2,i) else OJGte (r1,r2,i)
			| OpLte -> if jcond then OJGte (r2,r1,i) else OJLt (r2,r1,i)
			| _ -> assert false
		)
	| TBinop (OpAnd, e1, e2) ->
		assert false
	| TBinop (OpOr, e1, e2) ->
		assert false
	| _ ->
		let r = eval_expr ctx e in
		jump ctx (fun i -> if jcond then OJTrue (r,i) else OJFalse (r,i))

and eval_args ctx el t =
	List.map2 (fun e t -> eval_to ctx e t) el (match t with TFun (args,_) -> args | _ -> assert false)

and eval_expr ctx e =
	match e.eexpr with
	| TConst c ->
		(match c with
		| TInt i ->
			let r = alloc_tmp ctx TI32 in
			op ctx (OInt (r,alloc_i32 ctx i));
			r
		| TFloat f ->
			let r = alloc_tmp ctx TF64 in
			op ctx (OFloat (r,alloc_float ctx (float_of_string f)));
			r
		| Type.TBool b ->
			let r = alloc_tmp ctx TBool in
			op ctx (OBool (r,b));
			r
		| TThis ->
			0 (* first reg *)
		| _ ->
			failwith ("TODO " ^ s_const c))
	| TVar (v,e) ->
		let r = alloc_reg ctx v in
		(match e with
		| None -> ()
		| Some e ->
			let ri = eval_expr ctx e in
			op ctx (OMov (r,ri)));
		r
	| TLocal v ->
		alloc_reg ctx v
	| TReturn None ->
		let r = alloc_tmp ctx TVoid in
		op ctx (ORet r);
		r
	| TReturn (Some e) ->
		let r = eval_expr ctx e in
		op ctx (ORet r);
		alloc_tmp ctx TVoid
	| TParenthesis e ->
		eval_expr ctx e
	| TBlock el ->
		let rec loop = function
			| [e] -> eval_expr ctx e
			| [] -> alloc_tmp ctx TVoid
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
				let r = alloc_tmp ctx TVoid in
				let el = eval_args ctx el (to_type ctx f.cf_type) in
				op ctx (OCallN (r, alloc_fid ctx csup f, 0 :: el));
				r
			)
		| _ -> assert false);
	| TCall (ec,el) ->
		let ret = alloc_tmp ctx (to_type ctx e.etype) in
		let el = eval_args ctx el (to_type ctx ec.etype) in
		(match get_access ctx ec with
		| AStaticFun f ->
			(match el with
			| [] -> op ctx (OCall0 (ret, f))
			| [a] -> op ctx (OCall1 (ret, f, a))
			| [a;b] -> op ctx (OCall2 (ret, f, a, b))
			| [a;b;c] -> op ctx (OCall3 (ret, f, a, b, c))
			| [a;b;c;d] -> op ctx (OCall4 (ret, f, a, b, c, d))
			| _ -> op ctx (OCallN (ret, f, el)));
		| AInstanceFun (ethis, f) ->
			let el = eval_expr ctx ethis :: el in
			(match el with
			| [a] -> op ctx (OCall1 (ret, f, a))
			| [a;b] -> op ctx (OCall2 (ret, f, a, b))
			| [a;b;c] -> op ctx (OCall3 (ret, f, a, b, c))
			| [a;b;c;d] -> op ctx (OCall4 (ret, f, a, b, c, d))
			| _ -> op ctx (OCallN (ret, f, el)));
		| AInstanceProto (ethis, fid) ->
			let el = eval_expr ctx ethis :: el in
			op ctx (OCallMethod (ret, fid, el))
		| _ ->
			let r = eval_expr ctx ec in
			op ctx (OCallClosure (ret, r, el)); (* if it's a value, it's a closure *)
		);
		ret
	| TField (ec,a) ->
		let r = alloc_tmp ctx (to_type ctx e.etype) in
		(match get_access ctx e with
		| AGlobal g ->
			op ctx (OGetGlobal (r,g));
		| AStaticFun f ->
			op ctx (OGetFunction (r,f));
		| AInstanceFun (ethis, f) ->
			op ctx (OClosure (r, f, eval_expr ctx ethis))
		| AInstanceField (ethis,fid) ->
			let robj = eval_expr ctx ethis in
			op ctx (match ethis.eexpr with TConst TThis -> OGetThis (r,fid) | _ -> OField (r,robj,fid));
		| AInstanceProto (ethis,fid) ->
			let robj = eval_expr ctx ethis in
			op ctx (OMethod (r,robj,fid));
		| ANone | ALocal _ ->
			error "Invalid access" e.epos);
		r
	| TObjectDecl o ->
		(* TODO *)
		alloc_tmp ctx TVoid
	| TNew (c,pl,el) ->
		let r = alloc_tmp ctx (class_type ctx c) in
		op ctx (ONew r);
		(match c.cl_constructor with
		| None -> ()
		| Some { cf_expr = None } -> assert false
		| Some ({ cf_expr = Some { eexpr = TFunction({ tf_expr = { eexpr = TBlock([]) } }) } }) when el = [] -> ()
		| Some ({ cf_expr = Some cexpr } as constr) ->
			let rl = eval_args ctx el (to_type ctx cexpr.etype) in
			let ret = alloc_tmp ctx TVoid in
			let g = alloc_fid ctx c constr in
			op ctx (match rl with
			| [] -> OCall1 (ret,g,r)
			| [a] -> OCall2 (ret,g,r,a)
			| [a;b] -> OCall3 (ret,g,r,a,b)
			| [a;b;c] -> OCall4 (ret,g,r,a,b,c)
			| _ ->
				let rf = alloc_tmp ctx (global_type ctx g) in
				op ctx (OGetGlobal (rf,g));
				OCallN (ret,rf,r :: rl));
		);
		r
	| TIf (cond,eif,eelse) ->
		let out = alloc_tmp ctx (to_type ctx e.etype) in
		let j = jump_expr ctx cond false in
		op ctx (OMov (out,eval_expr ctx eif));
		(match eelse with
		| None -> j()
		| Some e ->
			let jexit = jump ctx (fun i -> OJAlways i) in
			j();
			op ctx (OMov (out,eval_expr ctx e));
			jexit());
		out
	| TBinop (bop, e1, e2) ->
		(match bop with
		| OpLte ->
			let r = alloc_tmp ctx TBool in
			let a = eval_expr ctx e1 in
			let b = eval_expr ctx e2 in
			op ctx (OGte (r,b,a));
			r
		| OpAdd ->
			let t = to_type ctx e.etype in
			let r = alloc_tmp ctx t in
			(match t with
			| TI32 | TF32 | TF64 | TUI8 ->
				let a = eval_to ctx e1 t in
				let b = eval_to ctx e2 t in
				op ctx (OAdd (r,a,b));
				r
			| _ ->
				assert false)
		| OpSub | OpMult ->
			let t = to_type ctx e.etype in
			let r = alloc_tmp ctx t in
			(match t with
			| TI32 | TF32 | TF64 | TUI8 ->
				let a = eval_to ctx e1 t in
				let b = eval_to ctx e2 t in
				(match bop with
				| OpSub -> op ctx (OSub (r,a,b))
				| OpMult -> op ctx (OMul (r,a,b))
				| _ -> assert false);
				r
			| _ ->
				assert false)
		| OpAssign ->
			let value = eval_to ctx e2 (to_type ctx e1.etype) in
			(match get_access ctx e1 with
			| AGlobal g ->
				op ctx (OSetGlobal (g,value))
			| AInstanceField ({ eexpr = TConst TThis }, fid) ->
				op ctx (OSetThis (fid,value))
			| AInstanceField (ethis, fid) ->
				op ctx (OSetField (eval_expr ctx ethis, fid, value))
			| ALocal r ->
				op ctx (OMov (r, value))
			| ANone | AInstanceFun _ | AInstanceProto _ | AStaticFun _ ->
				assert false);
			value
		| _ ->
			failwith ("TODO " ^ s_expr (s_type (print_context())) e))
	| TFunction f ->
		let fid = alloc_function_name ctx ("function#" ^ string_of_int (DynArray.length ctx.cfunctions)) in
		make_fun ctx fid f None;
		let r = alloc_tmp ctx (to_type ctx e.etype) in
		op ctx (OGetFunction (r, fid));
		r
	| _ ->
		failwith ("TODO " ^ s_expr (s_type (print_context())) e)

and make_fun ctx fidx f cthis =
	let old = ctx.m in
	ctx.m <- method_context();
	let tthis = (match cthis with
	| None -> None
	| Some c ->
		let t = to_type ctx (TInst (c,[])) in
		ignore(alloc_tmp ctx t); (* index 0 *)
		Some t
	) in
	let args = List.map (fun (v,o) ->
		let r = alloc_reg ctx v in
		(match o with
		| None | Some TNull -> ()
		| Some c ->
			op ctx (OJNotNull (r,1));
			match c with
			| TNull | TThis | TSuper -> assert false
			| TInt i -> op ctx (OInt (r, alloc_i32 ctx i))
			| TFloat s -> op ctx (OFloat (r, alloc_float ctx (float_of_string s)))
			| Type.TBool b -> op ctx (OBool (r, b))
			| TString s -> assert false (* TODO *)
		);
		rtype ctx r
	) f.tf_args in
	ignore(eval_expr ctx f.tf_expr);
	let tret = to_type ctx f.tf_type in
	if tret = TVoid then op ctx (ORet (alloc_tmp ctx TVoid));
	let f = {
		findex = fidx;
		ftype = TFun ((match tthis with None -> args | Some t -> t :: args), tret);
		regs = DynArray.to_array ctx.m.mregs.arr;
		code = DynArray.to_array ctx.m.mops;
	} in
	ctx.m <- old;
	DynArray.add ctx.cfunctions f

let generate_static ctx c f =
	match f.cf_kind with
	| Var _ | Method MethDynamic ->
		()
	| Method m ->
		make_fun ctx (alloc_fid ctx c f) (match f.cf_expr with Some { eexpr = TFunction f } -> f | _ -> assert false) None

let generate_member ctx c f =
	match f.cf_kind with
	| Var _ -> ()
	| Method m ->
		make_fun ctx (alloc_fid ctx c f) (match f.cf_expr with Some { eexpr = TFunction f } -> f | _ -> assert false) (Some c)

let generate_type ctx t =
	match t with
	| TClassDecl c when c.cl_extern ->
		List.iter (fun f ->
			List.iter (fun (name,args,pos) ->
				match name, args with
				| Meta.Custom ":hlNative", [EConst(String(name)),_] ->
					ignore(lookup ctx.cnatives name (fun() -> (alloc_string ctx name,to_type ctx f.cf_type,alloc_fid ctx c f)));
				| _ -> ()
			) f.cf_meta
		) c.cl_ordered_statics
	| TClassDecl c ->
		List.iter (generate_static ctx c) c.cl_ordered_statics;
		(match c.cl_constructor with
		| None -> ()
		| Some f -> generate_member ctx c f);
		List.iter (generate_member ctx c) c.cl_ordered_fields;
	| TTypeDecl _ ->
		()
	| TAbstractDecl a when a.a_impl = None ->
		()
	| TEnumDecl _ | TAbstractDecl _ ->
		failwith (s_type_path (t_infos t).mt_path)

let generate_static_init ctx =
	let exprs = ref [] in
	let t_void = ctx.com.basic.tvoid in
	List.iter (fun t ->
		match t with
		| TClassDecl c ->
			List.iter (fun f ->
				match f.cf_kind, f.cf_expr with
				| Var _, Some e | Method MethDynamic, Some e ->
					let p = e.epos in
					let e = mk (TBinop (OpAssign,(mk (TField (mk (TTypeExpr t) t_dynamic p,FStatic (c,f))) f.cf_type p), e)) f.cf_type p in
					exprs := e :: !exprs;
				| _ ->
					()
			) c.cl_ordered_statics;
		| _ -> ()
	) ctx.com.types;
	(match ctx.com.main_class with
	| None -> ()
	| Some m ->
		let t = (try List.find (fun t -> t_path t = m) ctx.com.types with Not_found -> assert false) in
		match t with
		| TClassDecl c ->
			let f = (try PMap.find "main" c.cl_statics with Not_found -> assert false) in
			let p = f.cf_pos in
			exprs := mk (TCall (mk (TField (mk (TTypeExpr t) t_dynamic p, FStatic (c,f))) f.cf_type p,[])) t_void p :: !exprs
		| _ ->
			assert false
	);
	let fid = alloc_function_name ctx "<entry>" in
	make_fun ctx fid { tf_expr = mk (TBlock (List.rev !exprs)) t_void null_pos; tf_args = []; tf_type = t_void } None;
	fid


(* ------------------------------- CHECK ---------------------------------------------- *)

let check code =
	let ftypes = Array.create (Array.length code.natives + Array.length code.functions) TVoid in

	let check_fun f =
		let pos = ref 0 in
		let error msg =
			failwith ("In function " ^ string_of_int f.findex ^ "@" ^ string_of_int (!pos) ^ " : " ^ msg)
		in
		let targs, tret = (match f.ftype with TFun (args,ret) -> args, ret | _ -> assert false) in
		let rtype i = f.regs.(i) in
		let rec same_type t1 t2 =
			if t1 == t2 then true else
			match t1, t2 with
			| TFun (args1,ret1), TFun (args2,ret2) when List.length args1 = List.length args2 -> List.for_all2 same_type args1 args2 && same_type ret1 ret2
			| TObj p1, TObj p2 ->
				let rec loop p =
					p.pname = p2.pname || (match p.psuper with None -> false | Some p -> loop p)
				in
				loop p1
			| _ -> false
		in
		let check t1 t2 =
			if not (same_type t1 t2) then error (tstr t1 ^ " should be " ^ tstr t2)
		in
		let reg r t =
			if not (same_type (rtype r) t) then error ("Register " ^ string_of_int r ^ " should be " ^ tstr t ^ " and not " ^ tstr (rtype r))
		in
		let numeric r =
			match rtype r with
			| TUI8 | TI32 | TF32 | TF64 -> ()
			| _ -> error ("Register " ^ string_of_int r ^ " should be numeric")
		in
		let int r =
			match rtype r with
			| TUI8 | TI32 -> ()
			| _ -> error ("Register " ^ string_of_int r ^ " should be integral")
		in
		let call f args r =
			match ftypes.(f) with
			| TFun (targs, tret) ->
				if List.length args <> List.length targs then assert false;
				List.iter2 reg args targs;
				reg r tret
			| _ -> assert false
		in
		let can_jump delta =
			if !pos + 1 + delta < 0 || !pos + 1 + delta >= Array.length f.code then failwith "Jump outside function bounds";
			if delta < 0 && Array.get f.code (!pos + 1 + delta) <> OLabel 0 then failwith "Jump back without Label";
		in
		let is_obj r =
			match rtype r with
			| TObj _ -> ()
			| _ -> error ("Register " ^ string_of_int r ^ " should be object")
		in
		let tfield o id proto =
			match rtype o with
			| TObj p ->
				let rec loop pl p =
					let pl = p :: pl in
					match p.psuper with
					| None ->
						let rec fetch id = function
							| [] -> assert false
							| p :: pl when proto ->
								let d = id - Array.length p.pproto in
								if d < 0 then
									let _, _, fid = p.pproto.(id) in
									ftypes.(fid)
								else
									fetch d pl
							| p :: pl ->
								let d = id - Array.length p.pfields in
								if d < 0 then
									let _, _, t = p.pfields.(id) in
									t
								else
									fetch d pl
						in
						fetch id pl
					| Some p ->
						loop pl p
				in
				loop [] p
			| _ ->
				is_obj o;
				TVoid
		in
		iteri reg targs;
		Array.iteri (fun i op ->
			pos := i;
			match op with
			| OMov (a,b) ->
				reg b (rtype a)
			| OInt (r,i) ->
				(match rtype r with
				| TUI8 ->
					let i = code.ints.(i) in
					if Int32.to_int i < 0 || Int32.to_int i > 0xFF then reg r TI32
				| TI32 -> ()
				| _ -> reg r TI32)
			| OFloat (r,i) ->
				if rtype r <> TF32 then reg r TF64;
				if i < 0 || i >= Array.length code.floats then failwith "float outside range"
			| OBool (r,_) ->
				reg r TBool
			| OAdd (r,a,b) | OSub (r,a,b) | OMul (r,a,b) | ODiv (r,a,b) ->
				numeric r;
				reg a (rtype r);
				reg b (rtype r);
			| OIncr r ->
				int r
			| ODecr r ->
				int r
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
			| OCallMethod (r, m, rl) ->
				(match rl with
				| [] -> assert false
				| obj :: _ ->
					match tfield obj m true with
					| TFun (targs, tret) when List.length targs = List.length rl -> List.iter2 reg rl targs; reg r tret
					| t -> check t (TFun (List.map rtype rl, rtype r)));
			| OCallClosure (r,f,rl) ->
				(match rtype f with
				| TFun (targs,tret) when List.length targs = List.length rl -> List.iter2 reg rl targs; reg r tret
				| _ -> reg f (TFun(List.map rtype rl,rtype r)))
			| OGetGlobal (r,g) | OSetGlobal (r,g) ->
				reg r code.globals.(g)
			| OEq (r,a,b) | ONotEq (r, a, b) | OLt (r, a, b) | OGte (r, a, b) ->
				reg r TBool;
				reg a (rtype b)
			| ORet r ->
				reg r tret
			| OJTrue (r,delta) | OJFalse (r,delta) ->
				reg r TBool;
				can_jump delta
			| OJNull (r,delta) | OJNotNull (r,delta) ->
				ignore(rtype r);
				can_jump delta
			| OJGte (a,b,delta) | OJLt (a,b,delta) | OJEq (a,b,delta) | OJNeq (a,b,delta) ->
				reg a (rtype b);
				can_jump delta
			| OJAlways d ->
				can_jump d
			| OToAny (r,a) ->
				ignore(rtype a);
				reg r TAny
			| OLabel _ ->
				()
			| ONew r ->
				is_obj r
			| OField (r,o,fid) | OSetField (o,fid,r) ->
				reg r (tfield o fid false)
			| OGetThis (r,fid) | OSetThis(fid,r) ->
				reg r (tfield 0 fid false)
			| OGetFunction (r,f) ->
				reg r ftypes.(f)
			| OMethod (r,o,fid) ->
				(match tfield o fid true with
				| TFun (t :: tl, tret) ->
					reg o t;
					reg r (TFun (tl,tret));
				| _ -> assert false)
			| OClosure (r,f,arg) ->
				(match ftypes.(f) with
				| TFun (t :: tl, tret) ->
					reg arg t;
					reg r (TFun (tl,tret));
				| _ -> assert false);
		) f.code
		(* TODO : check that all path correctly initialize NULL values and reach a return *)
	in
	Array.iter (fun fd -> ftypes.(fd.findex) <- fd.ftype) code.functions;
	Array.iter (fun (_,t,idx) -> ftypes.(idx) <- t) code.natives;
	Array.iter check_fun code.functions

(* ------------------------------- INTERP --------------------------------------------- *)

type value =
	| VNull
	| VInt of int32
	| VFloat of float
	| VBool of bool
	| VAny of value * ttype
	| VObj of vobject
	| VClosure of vfunction * value option

and vfunction =
	| FFun of fundecl
	| FNativeFun of string * (value list -> value)

and vobject = {
	vproto : vproto;
	vfields : value array;
}

and vproto = {
	vclass : class_proto;
	vmethods : vfunction array;
}

exception Return of value

let default t =
	match t with
	| TVoid | TFun _ | TAny | TObj _ -> VNull
	| TI32 | TUI8 -> VInt Int32.zero
	| TF32 | TF64 -> VFloat 0.
	| TBool -> VBool false

let rec vstr v =
	match v with
	| VNull -> "null"
	| VInt i -> Int32.to_string i ^ "i"
	| VFloat f -> string_of_float f ^ "f"
	| VBool b -> if b then "true" else "false"
	| VAny (v,t) -> "any(" ^ vstr v ^ ":" ^ tstr t ^ ")"
	| VObj o -> "#" ^ o.vproto.vclass.pname
	| VClosure (f,o) ->
		(match o with
		| None -> fstr f
		| Some v -> fstr f ^ "(" ^ vstr v ^ ")")

and fstr = function
	| FFun f -> "function@" ^ string_of_int f.findex
	| FNativeFun (s,_) -> "native[" ^ s ^ "]"

exception Runtime_error of string

let interp code =

	let globals = Array.map default code.globals in
	let functions = Array.create (Array.length code.functions + Array.length code.natives) (FNativeFun ("",(fun _ -> assert false))) in
	let cached_protos = Hashtbl.create 0 in

	let rec get_proto p =
		try
			Hashtbl.find cached_protos p.pname
		with Not_found ->
			let meths, fields = (match p.psuper with None -> [||],[||] | Some p -> let p,f = get_proto p in p.vmethods, f) in
			let meths = Array.append meths (Array.map (fun(_,_,f) -> functions.(f)) p.pproto) in
			let fields = Array.append fields (Array.map (fun (_,_,t) -> t) p.pfields) in
			let proto = ({ vclass = p; vmethods = meths },fields) in
			Hashtbl.replace cached_protos p.pname proto;
			proto
	in

	let new_obj t =
		match t with
		| TObj p ->
			let p, fields = get_proto p in
			{ vproto = p; vfields = Array.map default fields }
		| _ -> assert false
	in

	let error msg = raise (Runtime_error msg) in

	let rec call f args =
		let regs = Array.map default f.regs in
		iteri (fun i v -> regs.(i) <- v) args;
		let pos = ref 0 in
		let rtype i = f.regs.(i) in
		let set r v = Array.unsafe_set regs r v in
		let get r = Array.unsafe_get regs r in
		let global g = Array.unsafe_get globals g in
		let func f = Array.unsafe_get functions f in
		let numop iop fop a b =
			match rtype a with
			| TUI8 ->
				(match regs.(a), regs.(b) with
				| VInt a, VInt b -> VInt (Int32.logand (iop a b) 0xFFl)
				| _ -> assert false)
			| TI32 ->
				(match regs.(a), regs.(b) with
				| VInt a, VInt b -> VInt (iop a b)
				| _ -> assert false)
			| TF32 | TF64 ->
				(match regs.(a), regs.(b) with
				| VFloat a, VFloat b -> VFloat (fop a b)
				| _ -> assert false)
			| _ ->
				assert false
		in
		let iunop iop r =
			match rtype r with
			| TUI8 ->
				(match regs.(r) with
				| VInt a -> VInt (Int32.logand (iop a) 0xFFl)
				| _ -> assert false)
			| TI32 ->
				(match regs.(r) with
				| VInt a -> VInt (iop a)
				| _ -> assert false)
			| _ ->
				assert false
		in
		let fcall f args =
			match f with
			| FFun f -> call f args
			| FNativeFun (_,f) -> f args
		in
		let rec loop() =
			let op = f.code.(!pos) in
			incr pos;
			(match op with
			| OMov (a,b) -> set a (get b)
			| OInt (r,i) -> set r (VInt code.ints.(i))
			| OFloat (r,i) -> set r (VFloat (Array.unsafe_get code.floats i))
			| OBool (r,b) -> set r (VBool b)
			| OAdd (r,a,b) -> set r (numop Int32.add ( +. ) a b)
			| OSub (r,a,b) -> set r (numop Int32.sub ( -. ) a b)
			| OMul (r,a,b) -> set r (numop Int32.mul ( *. ) a b)
			| ODiv (r,a,b) -> set r (numop Int32.div ( /. ) a b)
			| OIncr r -> set r (iunop (fun i -> Int32.add i 1l) r)
			| ODecr r -> set r (iunop (fun i -> Int32.sub i 1l) r)
			| OCall0 (r,f) -> set r (fcall (func f) [])
			| OCall1 (r,f,r1) -> set r (fcall (func f) [get r1])
			| OCall2 (r,f,r1,r2) -> set r (fcall (func f) [get r1;get r2])
			| OCall3 (r,f,r1,r2,r3) -> set r (fcall (func f) [get r1;get r2;get r3])
			| OCall4 (r,f,r1,r2,r3,r4) -> set r (fcall (func f) [get r1;get r2;get r3;get r4])
			| OCallN (r,f,rl) -> set r (fcall (func f) (List.map get rl))
			| OGetGlobal (r,g) -> set r (global g)
			| OSetGlobal (r,g) -> Array.unsafe_set globals g (get r)
			| OEq (r,a,b) -> set r (VBool (get a = get b))
			| ONotEq (r,a,b) -> set r (VBool (get a <> get b))
			| OGte (r,a,b) -> set r (VBool (get a >= get b))
			| OLt (r,a,b) -> set r (VBool (get a < get b))
			| OJTrue (r,i) -> if get r = VBool true then pos := !pos + i
			| OJFalse (r,i) -> if get r = VBool false then pos := !pos + i
			| ORet r -> raise (Return regs.(r))
			| OJNull (r,i) -> if get r == VNull then pos := !pos + i
			| OJNotNull (r,i) -> if get r != VNull then pos := !pos + i
			| OJLt (a,b,i) -> if get a < get b then pos := !pos + i
			| OJGte (a,b,i) -> if get a >= get b then pos := !pos + i
			| OJEq (a,b,i) -> if get a = get b then pos := !pos + i
			| OJNeq (a,b,i) -> if get a <> get b then pos := !pos + i
			| OJAlways i -> pos := !pos + i
			| OToAny (r,a) -> set r (VAny (get a, f.regs.(a)))
			| OLabel _ -> ()
			| ONew r -> set r (VObj (new_obj (rtype r)))
			| OField (r,o,fid) ->
				set r (match get o with VObj v -> v.vfields.(fid) | VNull -> error "Null access" | _ -> assert false)
			| OSetField (o,fid,r) ->
				(match get o with
				| VObj v -> v.vfields.(fid) <- get r
				| VNull -> error "Null access"
				| _ -> assert false)
			| OGetThis (r, fid) ->
				set r (match get 0 with VObj v -> v.vfields.(fid) | _ -> assert false)
			| OSetThis (fid, r) ->
				(match get 0 with
				| VObj v -> v.vfields.(fid) <- get r
				| _ -> assert false)
			| OCallMethod (r,m,rl) ->
				(match get (List.hd rl) with
				| VObj v -> set r (fcall v.vproto.vmethods.(m) (List.map get rl))
				| VNull -> error "Null access"
				| _ -> assert false)
			| OCallClosure (r,v,rl) ->
				(match get v with
				| VClosure (f,None) -> set r (fcall f (List.map get rl))
				| VClosure (f,Some arg) -> set r (fcall f (arg :: List.map get rl))
				| VNull -> error "Null function"
				| _ -> assert false)
			| OGetFunction (r, fid) ->
				let f = functions.(fid) in
				set r (VClosure (f,None))
			| OClosure (r, fid, v) ->
				let f = functions.(fid) in
				set r (VClosure (f,Some (get v)))
			| OMethod (r, o, m) ->
				(match get o with
				| VObj v as obj -> set r (VClosure (v.vproto.vmethods.(m), Some obj))
				| VNull -> error "Null access"
				| _ -> assert false)
			);
			loop()
		in
		try
			loop()
		with
			Return v -> v
	in
	let load_native name =
		FNativeFun (name,match name with
		| "std@log" -> (fun args -> print_endline (vstr (List.hd args)); VNull);
		| _ -> (fun args -> error ("Unresolved native " ^ name))
		)
	in
	Array.iter (fun (name,_,idx) -> functions.(idx) <- load_native code.strings.(name)) code.natives;
	Array.iter (fun fd -> functions.(fd.findex) <- FFun fd) code.functions;
	match functions.(code.entrypoint) with
	| FFun f when f.ftype = TFun([],TVoid) -> call f []
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

	let types = new_lookup() in
	let byte = IO.write_byte ch in
	let write_index = write_index_gen byte in

	let rec write_type t =
		write_index (lookup types t (fun() -> assert false))
	in

	let write_op op =

		let o = Obj.repr op in
		let oid = Obj.tag o in

		match op with
		| OLabel _ ->
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
		| OCallN (r,f,rl) | OCallClosure (r,f,rl) | OCallMethod (r,f,rl) ->
			byte oid;
			write_index r;
			write_index f;
			let n = List.length rl in
			if n > 0xFF then assert false;
			byte n;
			List.iter write_index rl
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

	let rec get_type t =
		ignore(lookup types t (fun() ->
			(match t with
			| TFun (args, ret) ->
				List.iter get_type args;
				get_type ret
			| TObj p ->
				(match p.psuper with None -> () | Some p -> get_type (TObj p));
				Array.iter (fun (_,n,t) -> get_type t) p.pfields
			| _ ->
				());
			t
		));
	in
	List.iter (fun t -> get_type t) [TVoid; TUI8; TI32; TF32; TF64; TBool; TAny]; (* make sure all basic types get lower indexes *)
	Array.iter (fun g -> get_type g) code.globals;
	Array.iter (fun (_,t,_) -> get_type t) code.natives;
	Array.iter (fun f -> get_type f.ftype; Array.iter (fun r -> get_type r) f.regs) code.functions;

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
		| TVoid -> byte 0
		| TUI8 -> byte 1
		| TI32 -> byte 2
		| TF32 -> byte 3
		| TF64 -> byte 4
		| TBool -> byte 5
		| TAny -> byte 6
		| TFun (args,ret) ->
			let n = List.length args in
			if n > 0xFF then assert false;
			byte 7;
			byte n;
			List.iter write_type args;
			write_type ret
		| TObj p ->
			byte 8;
			write_index p.pid;
			(match p.psuper with
			| None -> write_index (-1)
			| Some t -> write_type (TObj t));
			write_index (Array.length p.pfields);
			write_index (Array.length p.pproto);
			Array.iter (fun (_,n,t) -> write_index n; write_type t) p.pfields;
			Array.iter (fun (_,n,g) -> write_index n; write_index g) p.pproto;
	) types.arr;

	Array.iter write_type code.globals;
	Array.iter (fun (name_index,ttype,findex) ->
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
	| OBool (r,b) -> if b then Printf.sprintf "true %d" r else Printf.sprintf "false %d" r
	| OAdd (r,a,b) -> Printf.sprintf "add %d,%d,%d" r a b
	| OSub (r,a,b) -> Printf.sprintf "sub %d,%d,%d" r a b
	| OMul (r,a,b) -> Printf.sprintf "mul %d,%d,%d" r a b
	| ODiv (r,a,b) -> Printf.sprintf "div %d,%d,%d" r a b
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
	| OGetFunction (r,f) -> Printf.sprintf "getfunction %d, f%d" r f
	| OClosure (r,f,v) -> Printf.sprintf "closure %d, f%d(%d)" r f v
	| OGetGlobal (r,g) -> Printf.sprintf "global %d, %d" r g
	| OSetGlobal (g,r) -> Printf.sprintf "setglobal %d, %d" g r
	| OEq (r,a,b) -> Printf.sprintf "eq %d,%d,%d" r a b
	| ONotEq (r,a,b)  -> Printf.sprintf "noteq %d,%d,%d" r a b
	| OLt (r,a,b) -> Printf.sprintf "lt %d,%d,%d" r a b
	| OGte (r,a,b) -> Printf.sprintf "gte %d,%d,%d" r a b
	| ORet r -> Printf.sprintf "ret %d" r
	| OJTrue (r,d) -> Printf.sprintf "jtrue %d,%d" r d
	| OJFalse (r,d) -> Printf.sprintf "jfalse %d,%d" r d
	| OJNull (r,d) -> Printf.sprintf "jnull %d,%d" r d
	| OJNotNull (r,d) -> Printf.sprintf "jnotnull %d,%d" r d
	| OJLt (a,b,i) -> Printf.sprintf "jlt %d,%d,%d" a b i
	| OJGte (a,b,i) -> Printf.sprintf "jgte %d,%d,%d" a b i
	| OJEq (a,b,i) -> Printf.sprintf "jeq %d,%d,%d" a b i
	| OJNeq (a,b,i) -> Printf.sprintf "jneq %d,%d,%d" a b i
	| OJAlways d -> Printf.sprintf "jalways %d" d
	| OToAny (r,a) -> Printf.sprintf "toany %d,%d" r a
	| OLabel _ -> "label"
	| ONew r -> Printf.sprintf "new %d" r
	| OField (r,o,i) -> Printf.sprintf "field %d,%d[%d]" r o i
	| OMethod (r,o,m) -> Printf.sprintf "method %d,%d[%d]" r o m
	| OSetField (o,i,r) -> Printf.sprintf "setfield %d[%d],%d" o i r
	| OGetThis (r,i) -> Printf.sprintf "getthis %d,[%d]" r i
	| OSetThis (i,r) -> Printf.sprintf "setthis [%d],%d" i r

let dump code =
	let lines = ref [] in
	let pr s =
		lines := s :: !lines
	in
	let all_protos = Hashtbl.create 0 in
	let tstr t =
		(match t with
		| TObj p -> Hashtbl.replace all_protos p.pname p
		| _ -> ());
		tstr t
	in
	let str idx =
		try
			code.strings.(idx)
		with _ ->
			"INVALID:" ^ string_of_int idx
	in
	pr ("hl v" ^ string_of_int code.version);
	pr ("entry @" ^ string_of_int code.entrypoint);
	pr (string_of_int (Array.length code.strings) ^ " strings");
	Array.iteri (fun i s ->
		pr ("	@" ^ string_of_int i ^ " : " ^ s);
	) code.strings;
	pr (string_of_int (Array.length code.ints) ^ " ints");
	Array.iteri (fun i v ->
		pr ("	@" ^ string_of_int i ^ " : " ^ Int32.to_string v);
	) code.ints;
	pr (string_of_int (Array.length code.floats) ^ " floats");
	Array.iteri (fun i f ->
		pr ("	@" ^ string_of_int i ^ " : " ^ string_of_float f);
	) code.floats;
	pr (string_of_int (Array.length code.globals) ^ " globals");
	Array.iteri (fun i g ->
		pr ("	@" ^ string_of_int i ^ " : " ^ tstr g);
	) code.globals;
	pr (string_of_int (Array.length code.natives) ^ " natives");
	Array.iter (fun (name,t,fidx) ->
		pr ("	@" ^ string_of_int fidx ^ " native " ^ str name ^ " " ^ tstr t);
	) code.natives;
	pr (string_of_int (Array.length code.functions) ^ " functions");
	Array.iter (fun f ->
		pr ("	@" ^ string_of_int f.findex ^ " fun " ^ tstr f.ftype);
		Array.iteri (fun i r ->
			pr ("		r" ^ string_of_int i ^ " " ^ tstr r);
		) f.regs;
		Array.iteri (fun i o ->
			pr ("		@"  ^ string_of_int i ^ " " ^ ostr o);
		) f.code;
	) code.functions;
	let protos = Hashtbl.fold (fun _ p acc -> p :: acc) all_protos [] in
	pr (string_of_int (List.length protos) ^ " objects protos");
	List.iter (fun p ->
		pr ("	" ^ p.pname);
		(match p.psuper with
		| None -> ()
		| Some p -> pr ("		extends " ^ p.pname));
		pr ("		" ^ string_of_int (Array.length p.pfields) ^ " fields");
		Array.iteri (fun i (_,id,t) ->
			pr ("		  @" ^ string_of_int i ^ " " ^ str id ^ " " ^ tstr t)
		) p.pfields;
		pr ("		" ^ string_of_int (Array.length p.pproto) ^ " methods");
		Array.iteri (fun i (_,id,m) ->
			pr ("		  @" ^ string_of_int i ^ " " ^ str id ^ " fun@" ^ string_of_int m)
		) p.pproto;
	) protos;
	String.concat "\n" (List.rev !lines)


(* --------------------------------------------------------------------------------------------------------------------- *)

let generate com =
	let ctx = {
		com = com;
		m = method_context();
		cints = new_lookup();
		cstrings = new_lookup();
		cfloats = new_lookup();
		cglobals = new_lookup();
		cnatives = new_lookup();
		cfunctions = DynArray.create();
		overrides = Hashtbl.create 0;
		cached_types = PMap.empty;
		cfids = new_lookup();
	} in
	ignore(alloc_string ctx "");
	let all_classes = Hashtbl.create 0 in
	List.iter (fun t ->
		match t with
		| TClassDecl c ->
			let rec loop p f =
				match p with
				| Some (p,_) when PMap.mem f.cf_name p.cl_fields ->
					Hashtbl.replace ctx.overrides (f.cf_name,p.cl_path) true;
					loop p.cl_super f
				| _ -> ()
			in
			List.iter (fun f -> loop c.cl_super f) c.cl_overrides;
			Hashtbl.add all_classes c.cl_path c
 		| _ -> ()
	) com.types;
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
	} in
	if Common.defined com Define.Dump then prerr_endline (dump code);
	check code;
	let ch = IO.output_string() in
	write_code ch code;
	let str = IO.close_out ch in
	let ch = open_out_bin com.file in
	output_string ch str;
	close_out ch;
	if Common.defined com Define.Interp then ignore(interp code)

