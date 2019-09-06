open Globals
open Ast
open Type

open HxbChunks
open HxbEnums

exception HxbReadFailure of string

class hxb_reader
	(file_ch : IO.input)
	(resolve_type : path -> module_type)
	= object(self)

	val mutable ch : IO.input = file_ch

	val mutable chunks : hxb_chunk list option = None

	val mutable last_header : hxb_chunk_header option = None
	val mutable last_string_pool : hxb_chunk_string_pool option = None
	val mutable last_doc_pool : hxb_chunk_doc_pool option = None
	val mutable last_type_list : hxb_chunk_type_list option = None
	val mutable last_field_list : hxb_chunk_field_list option = None
	val mutable last_type_declarations : hxb_chunk_type_declarations option = None
	val mutable last_module_extra : hxb_chunk_module_extra option = None

	val mutable last_file = ""
	val mutable last_delta = 0

	val mutable built_classes : tclass array option = None
	val mutable built_enums : tenum array option = None
	val mutable built_abstracts : tabstract array option = None
	val mutable built_typedefs : tdef array option = None

	val mutable current_module : module_def option = None

	(* Primitives *)

	method read_u8 () =
		IO.read_byte ch

	method read_u32 () =
		IO.read_real_i32 ch

	method read_f64 () =
		IO.read_double ch

	method read_uleb128 () =
		let b = self#read_u8 () in
		if b >= 0x80 then
			(b land 0x7F) lor ((self#read_uleb128 ()) lsl 7)
		else
			b

	method read_leb128 () =
		let rec read acc shift =
			let b = self#read_u8 () in
			let acc = ((b land 0x7F) lsl shift) lor acc in
			if b >= 0x80 then
				read acc (shift + 7)
			else
				(b, acc, shift + 7)
		in
		let last, acc, shift = read 0 0 in
		let res = (if (last land 0x40) <> 0 then
			acc lor ((lnot 0) lsl shift)
		else
			acc) in
		res

	method read_str_raw len =
		IO.really_nread ch len

	method read_str () =
		Bytes.unsafe_to_string (self#read_str_raw (self#read_uleb128 ()))

	method read_list_indexed : 'b . (int -> 'b) -> 'b list = fun f ->
		(* TODO: reverse lists in storage *)
		let rec read n =
			if n = 0 then
				[]
			else
				(f n) :: (read (n - 1))
		in
		let len = self#read_uleb128 () in
		List.rev (read len)

	method read_list : 'b . (unit -> 'b) -> 'b list = fun f ->
		self#read_list_indexed (fun _ -> f ())

	method read_arr : 'b . (unit -> 'b) -> 'b array = fun f ->
		Array.init (self#read_uleb128 ()) (fun _ -> f ())

	method read_pmap : 'b 'c . (unit -> 'b * 'c) -> ('b, 'c) PMap.t = fun f ->
		let l = self#read_list f in
		List.fold_left (fun map (k, v) -> PMap.add k v map) PMap.empty l

	method read_hashtbl : 'b 'c . (unit -> 'b * 'c) -> ('b, 'c) Hashtbl.t = fun f ->
		let l = self#read_list f in
		List.fold_left (fun map (k, v) -> Hashtbl.add map k v; map) (Hashtbl.create 0) l

	method read_bool () =
		(self#read_u8 ()) <> 0

	method read_bools n =
		let b = self#read_u8 () in
		let rec read i =
			if i = n then
				[]
			else
				((b land (1 lsl i)) <> 0) :: (read (i + 1))
		in
		read 0

	method read_bools2 () = match self#read_bools 2 with
		| [a; b] -> a, b
		| _ -> assert false
	method read_bools3 () = match self#read_bools 3 with
		| [a; b; c] -> a, b, c
		| _ -> assert false
	method read_bools4 () = match self#read_bools 4 with
		| [a; b; c; d] -> a, b, c, d
		| _ -> assert false
	method read_bools5 () = match self#read_bools 5 with
		| [a; b; c; d; e] -> a, b, c, d, e
		| _ -> assert false

	method read_enum : 'b . (int -> 'b) -> 'b = fun f ->
		f (self#read_u8 ())

	method read_nullable : 'b . (unit -> 'b) -> 'b option = fun f ->
		if (self#read_u8 ()) <> 0 then
			Some (f ())
		else
			None

	method read_delta () =
		let v = self#read_leb128 () in
		last_delta <- last_delta + v;
		last_delta

	(* Haxe, globals.ml and misc *)

	method read_pos () =
		if not (Option.get last_header).config_store_positions; then
			null_pos
		else
			let pmin = self#read_delta () in
			let pmax_flag = self#read_leb128 () in
			let pmax, file_present = pmax_flag asr 1, (pmax_flag land 1) <> 0 in
			if file_present then
				last_file <- self#read_pstr ();
			{pfile = last_file; pmin; pmax}

	method read_path () =
		let t1 = self#read_list self#read_pstr in
		let t2 = self#read_pstr () in
		t1, t2

	method read_upath () =
		let t1 = self#read_list self#read_str in
		let t2 = self#read_str () in
		t1, t2

	method read_pstr () =
		(Option.get last_string_pool).data.(self#read_uleb128 ())

	method resolve_class index =
		let type_list = Option.get last_type_list in
		if index >= 0 then
			let built_classes = Option.get built_classes in
			built_classes.(index)
		else
			let index = -index - 1 in
			match (resolve_type type_list.external_classes.(index)) with
				| TClassDecl t -> t
				| _ -> raise (HxbReadFailure "expected class type")

	method read_class_ref () =
		self#resolve_class (self#read_leb128 ())

	method resolve_enum index =
		let type_list = Option.get last_type_list in
		if index >= 0 then
			let built_enums = Option.get built_enums in
			built_enums.(index)
		else
			let index = -index - 1 in
			match (resolve_type type_list.external_enums.(index)) with
				| TEnumDecl t -> t
				| _ -> raise (HxbReadFailure "expected class type")

	method read_enum_ref () =
		self#resolve_enum (self#read_leb128 ())

	method resolve_abstract index =
		let type_list = Option.get last_type_list in
		if index >= 0 then
			let built_abstracts = Option.get built_abstracts in
			built_abstracts.(index)
		else
			let index = -index - 1 in
			match (resolve_type type_list.external_abstracts.(index)) with
				| TAbstractDecl t -> t
				| _ -> raise (HxbReadFailure "expected class type")

	method read_abstract_ref () =
		self#resolve_abstract (self#read_leb128 ())

	method resolve_typedef index =
		let type_list = Option.get last_type_list in
		if index >= 0 then
			let built_typedefs = Option.get built_typedefs in
			built_typedefs.(index)
		else
			let index = -index - 1 in
			match (resolve_type type_list.external_typedefs.(index)) with
				| TTypeDecl t -> t
				| _ -> raise (HxbReadFailure "expected class type")

	method read_typedef_ref () =
		self#resolve_typedef (self#read_leb128 ())

	method read_class_field_ref t =
		let field_name = self#read_pstr () in
		if PMap.mem field_name t.cl_fields then
			PMap.find field_name t.cl_fields
		else
			PMap.find field_name t.cl_statics

	method read_enum_field_ref t =
		let field_name = self#read_pstr () in
		PMap.find field_name t.e_constrs

	method read_forward_type () =
		let t1 = self#read_pstr () in
		let t2 = self#read_pos () in
		let t3 = self#read_pos () in
		t1, t2, t3, (self#read_bool ())

	method read_forward_field () =
		let t1 = self#read_pstr () in
		let t2 = self#read_pos () in
		t1, t2, (self#read_pos ())

	(* Haxe, ast.ml *)

	method read_binop () =
		self#read_enum HxbEnums.Binop.from_int

	method read_unop () =
		self#read_enum HxbEnums.Unop.from_int

	method read_constant () = self#read_enum (function
		| 0 -> Int (self#read_pstr ())
		| 1 -> Float (self#read_pstr ())
		| 2 -> Ident (self#read_pstr ())
		| 3 ->
			let t1 = self#read_pstr () in 
			Regexp (t1, self#read_pstr ())
		| 4 -> String (self#read_pstr (), SDoubleQuotes)
		| 5 -> String (self#read_pstr (), SSingleQuotes)
		| _ -> raise (HxbReadFailure "read_constant"))

	method read_type_path () =
		let tpackage = self#read_list self#read_pstr in
		let tname = self#read_pstr () in
		let tparams = self#read_list self#read_type_param in
		let tsub = self#read_nullable self#read_pstr in
		{tpackage; tname; tparams; tsub}

	method read_placed_type_path () =
		let t1 = self#read_type_path () in
		t1, (self#read_pos ())

	method read_type_param () = self#read_enum (function
		| 0 -> TPType (self#read_type_hint ())
		| 1 -> TPExpr (self#read_expr ())
		| _ -> raise (HxbReadFailure "read_type_param"))

	method read_complex_type () = self#read_enum (function
		| 0 -> CTPath (self#read_type_path ())
		| 1 ->
			let t1 = self#read_list self#read_type_hint in
			CTFunction (t1, self#read_type_hint ())
		| 2 -> CTAnonymous (self#read_list self#read_field)
		| 3 -> CTParent (self#read_type_hint ())
		| 4 ->
			let t1 = self#read_list self#read_placed_type_path in
			CTExtend (t1, self#read_list self#read_field)
		| 5 -> CTOptional (self#read_type_hint ())
		| 6 ->
			let t1 = self#read_placed_name () in
			CTNamed (t1, self#read_type_hint ())
		| 7 -> CTIntersection (self#read_list self#read_type_hint)
		| _ -> raise (HxbReadFailure "read_complex_type"))

	method read_type_hint () =
		let t1 = self#read_complex_type () in
		t1, (self#read_pos ())

	method read_function () =
		let f_params = self#read_list self#read_type_param_decl in
		let f_args = self#read_list self#read_function_arg in
		let f_type = self#read_nullable self#read_type_hint in
		let f_expr = self#read_nullable self#read_expr in
		{f_params; f_args; f_type; f_expr}

	method read_function_arg () =
		let t1 = self#read_placed_name () in
		let t2 = self#read_bool () in
		let t3 = self#read_list self#read_metadata_entry in
		let t4 = self#read_nullable self#read_type_hint in
		t1, t2, t3, t4, (self#read_nullable self#read_expr)

	method read_placed_name () =
		let t1 = self#read_pstr () in
		t1, (self#read_pos ())

	method read_expr_def () = self#read_enum (function
		| 0 -> EConst (self#read_constant ())
		| 1 ->
			let t1 = self#read_expr () in
			EArray (t1, self#read_expr ())
		| 2 ->
			let t1 = self#read_binop () in
			let t2 = self#read_expr () in
			EBinop (t1, t2, self#read_expr ())
		| 3 ->
			let t1 = self#read_expr () in
			EField (t1, self#read_pstr ())
		| 4 -> EParenthesis (self#read_expr ())
		| 5 -> EObjectDecl (self#read_list self#read_object_field)
		| 6 -> EArrayDecl (self#read_list self#read_expr)
		| 7 ->
			let t1 = self#read_expr () in
			ECall (t1, self#read_list self#read_expr)
		| 8 ->
			let t1 = self#read_placed_type_path () in
			ENew (t1, self#read_list self#read_expr)
		| 9 ->
			let op, flag = self#read_unop () in
			EUnop (op, flag, self#read_expr ())
		| 10 -> EVars (self#read_list self#read_var)
		| 11 -> EFunction (FKAnonymous, self#read_function ())
		| 12 ->
			let t1 = self#read_placed_name () in
			let t2 = self#read_bool () in
			EFunction (FKNamed (t1, t2), self#read_function ())
		| 13 -> EFunction (FKArrow, self#read_function ())
		| 14 -> EBlock (self#read_list self#read_expr)
		| 15 ->
			let t1 = self#read_expr () in
			EFor (t1, self#read_expr ())
		| 16 ->
			let t1 = self#read_expr () in
			EIf (t1, self#read_expr (), None)
		| 17 ->
			let t1 = self#read_expr () in
			let t2 = self#read_expr () in
			EIf (t1, t2, Some (self#read_expr ()))
		| 18 ->
			let t1 = self#read_expr () in
			EWhile (t1, self#read_expr (), NormalWhile)
		| 19 ->
			let t1 = self#read_expr () in
			EWhile (t1, self#read_expr (), DoWhile)
		| 20 ->
			let t1 = self#read_expr () in
			ESwitch (t1, self#read_list self#read_case, None)
		| 21 ->
			let t1 = self#read_expr () in
			let t2 = self#read_list self#read_case in
			ESwitch (t1, t2, Some (None, self#read_pos ()))
		| 22 ->
			let e = self#read_expr () in
			let cases = self#read_list self#read_case in
			let edef = self#read_expr () in
			ESwitch (e, cases, Some ((Some edef), snd edef))
		| 23 ->
			let t1 = self#read_expr () in
			ETry (t1, [self#read_catch ()])
		| 24 ->
			let t1 = self#read_expr () in
			ETry (t1, self#read_list self#read_catch)
		| 25 -> EReturn None
		| 26 -> EReturn (Some (self#read_expr ()))
		| 27 -> EBreak
		| 28 -> EContinue
		| 29 -> EUntyped (self#read_expr ())
		| 30 -> EThrow (self#read_expr ())
		| 31 -> ECast (self#read_expr (), None)
		| 32 ->
			let t1 = self#read_expr () in
			ECast (t1, Some (self#read_type_hint ()))
		| 33 -> EDisplay (self#read_expr (), DKCall)
		| 34 -> EDisplay (self#read_expr (), DKDot)
		| 35 -> EDisplay (self#read_expr (), DKStructure)
		| 36 -> EDisplay (self#read_expr (), DKMarked)
		| 37 -> EDisplay (self#read_expr (), DKPattern false)
		| 38 -> EDisplay (self#read_expr (), DKPattern true)
		| 39 -> EDisplayNew (self#read_placed_type_path ())
		| 40 ->
			let t1 = self#read_expr () in
			let t2 = self#read_expr () in
			ETernary (t1, t2, self#read_expr ())
		| 41 ->
			let t1 = self#read_expr () in
			ECheckType (t1, self#read_type_hint ())
		| 42 ->
			let t1 = self#read_metadata_entry () in
			EMeta (t1, self#read_expr ())
		| _ -> raise (HxbReadFailure "read_expr_def"))

	method read_object_field () =
		let t1 = self#read_pstr () in
		let t2 = self#read_pos () in
		let t3 = (if (self#read_bool ()) then DoubleQuotes else NoQuotes) in
		(t1, t2, t3), (self#read_expr ())

	method read_var () =
		let t1 = self#read_placed_name () in
		let t2 = self#read_bool () in
		let t3 = self#read_nullable self#read_type_hint in
		t1, t2, t3, (self#read_nullable self#read_expr)

	method read_case () =
		let t1 = self#read_list self#read_expr in
		let t2 = self#read_nullable self#read_expr in
		let t3 = self#read_nullable self#read_expr in
		t1, t2, t3, (self#read_pos ())

	method read_catch () =
		let t1 = self#read_placed_name () in
		let t2 = self#read_type_hint () in
		let t3 = self#read_expr () in
		t1, t2, t3, (self#read_pos ())

	method read_expr () =
		let t1 = self#read_expr_def () in
		t1, (self#read_pos ())

	method read_type_param_decl () =
		let tp_name = self#read_placed_name () in
		let tp_params = self#read_list self#read_type_param_decl in
		let tp_constraints = self#read_nullable self#read_type_hint in
		let tp_meta = self#read_list self#read_metadata_entry in
		{tp_name; tp_params; tp_constraints; tp_meta}

	method read_doc () =
		let index = self#read_uleb128 () in
		if (index = 0) || (last_doc_pool = None) then
			None
		else
			Some ((Option.get last_doc_pool).data.(index - 1))

	method read_metadata_entry () =
		let t1 = Meta.from_string (self#read_pstr ()) in
		let t2 = self#read_list self#read_expr in
		t1, t2, (self#read_pos ())

	method read_placed_access () =
		let t1 = self#read_enum HxbEnums.Access.from_int in
		t1, (self#read_pos ())

	method read_field () =
		let cff_name = self#read_placed_name () in
		let cff_doc = self#read_doc () in
		let cff_pos = self#read_pos () in
		let cff_meta = self#read_list self#read_metadata_entry in
		let cff_access = self#read_list self#read_placed_access in
		let cff_kind = self#read_enum (function
			| 0 ->
				let t1 = self#read_nullable self#read_type_hint in
				FVar (t1, self#read_nullable self#read_expr)
			| 1 -> FFun (self#read_function ())
			| v when (v >= 2) && (v <= 26) ->
				let pos1 = self#read_pos () in
				let pos2 = self#read_pos () in
				let t = self#read_nullable self#read_type_hint in
				let e = self#read_nullable self#read_expr in
				(match v with
					| 2 -> FProp (("get", pos1), ("get", pos2), t, e)
					| 3 -> FProp (("get", pos1), ("set", pos2), t, e)
					| 4 -> FProp (("get", pos1), ("null", pos2), t, e)
					| 5 -> FProp (("get", pos1), ("default", pos2), t, e)
					| 6 -> FProp (("get", pos1), ("never", pos2), t, e)
					| 7 -> FProp (("set", pos1), ("get", pos2), t, e)
					| 8 -> FProp (("set", pos1), ("set", pos2), t, e)
					| 9 -> FProp (("set", pos1), ("null", pos2), t, e)
					| 10 -> FProp (("set", pos1), ("default", pos2), t, e)
					| 11 -> FProp (("set", pos1), ("never", pos2), t, e)
					| 12 -> FProp (("null", pos1), ("get", pos2), t, e)
					| 13 -> FProp (("null", pos1), ("set", pos2), t, e)
					| 14 -> FProp (("null", pos1), ("null", pos2), t, e)
					| 15 -> FProp (("null", pos1), ("default", pos2), t, e)
					| 16 -> FProp (("null", pos1), ("never", pos2), t, e)
					| 17 -> FProp (("default", pos1), ("get", pos2), t, e)
					| 18 -> FProp (("default", pos1), ("set", pos2), t, e)
					| 19 -> FProp (("default", pos1), ("null", pos2), t, e)
					| 20 -> FProp (("default", pos1), ("default", pos2), t, e)
					| 21 -> FProp (("default", pos1), ("never", pos2), t, e)
					| 22 -> FProp (("never", pos1), ("get", pos2), t, e)
					| 23 -> FProp (("never", pos1), ("set", pos2), t, e)
					| 24 -> FProp (("never", pos1), ("null", pos2), t, e)
					| 25 -> FProp (("never", pos1), ("default", pos2), t, e)
					| 26 -> FProp (("never", pos1), ("never", pos2), t, e)
					| _ -> assert false)
			| _ -> raise (Invalid_argument "enum")) in
		{cff_name; cff_doc; cff_pos; cff_meta; cff_access; cff_kind}

	(* Haxe, type.ml *)

	method read_type () = self#read_enum (function
		| 0 -> TMono (ref None)
		| 1 -> TMono (ref (Some (self#read_type ())))
		| 2 -> TEnum (self#read_enum_ref (), [])
		| 3 ->
			let t1 = self#read_enum_ref () in
			TEnum (t1, self#read_list self#read_type)
		| 4 -> TInst (self#read_class_ref (), [])
		| 5 ->
			let t1 = self#read_class_ref () in
			TInst (t1, self#read_list self#read_type)
		| 6 -> TType (self#read_typedef_ref (), [])
		| 7 ->
			let t1 = self#read_typedef_ref () in
			TType (t1, self#read_list self#read_type)
		| 8 ->
			let t1 = self#read_list self#read_tfun_arg in
			TFun (t1, self#read_type ())
		| 9 -> TAnon (self#read_anon_type ())
		| 10 -> t_dynamic
		| 11 -> TDynamic (self#read_type ())
		| 12 -> TAbstract (self#read_abstract_ref (), [])
		| 13 ->
			let t1 = self#read_abstract_ref () in
			TAbstract (t1, self#read_list self#read_type)
		| _ -> raise (HxbReadFailure "read_type"))

	method read_tfun_arg () =
		let t1 = self#read_pstr () in
		let t2 = self#read_bool () in
		t1, t2, (self#read_type ())

	method read_type_params () =
		self#read_list (fun () ->
			let t1 = self#read_pstr () in
			t1, (self#read_type ()))

	method read_tconstant () = self#read_enum (function
		| 0 -> TInt (Int32.of_int (self#read_leb128 ())) (* TODO *)
		| 1 -> TFloat (self#read_pstr ())
		| 2 -> TString (self#read_pstr ())
		| 3 -> TBool false
		| 4 -> TBool true
		| 5 -> TNull
		| 6 -> TThis
		| 7 -> TSuper
		| _ -> raise (HxbReadFailure "read_tconstant"))

	method read_tvar_extra () =
		let t1 = self#read_type_params () in
		t1, (self#read_nullable self#read_typed_expr)

	method read_tvar () =
		let v_id = self#read_leb128 () in
		let v_name = self#read_pstr () in
		let v_type = self#read_type () in
		let v_kind = self#read_enum HxbEnums.TVarKind.from_int in
		let v_capture, v_final = self#read_bools2 () in
		let v_extra = self#read_nullable self#read_tvar_extra in
		let v_meta = self#read_list self#read_metadata_entry in
		let v_pos = self#read_pos () in
		{v_id; v_name; v_type; v_kind; v_capture; v_final; v_extra; v_meta; v_pos}

	method read_tfunc () =
		let tf_args = self#read_list self#read_tfunc_arg in
		let tf_type = self#read_type () in
		let tf_expr = self#read_typed_expr () in
		{tf_args; tf_type; tf_expr}

	method read_tfunc_arg () =
		let t1 = self#read_tvar () in
		t1, (self#read_nullable self#read_typed_expr)

	method read_anon_type () =
		let a_fields = PMap.empty in (* TODO *)
		let a_status = ref (self#read_enum (function
			| 0 -> Closed
			| 1 -> Opened
			| 2 -> Const
			| 3 -> Extend (self#read_list self#read_type)
			| 4 -> Statics (self#read_class_ref ())
			| 5 -> EnumStatics (self#read_enum_ref ())
			| 6 -> AbstractStatics (self#read_abstract_ref ())
			| _ -> raise (HxbReadFailure "read_anon_type"))) in
		{a_fields; a_status}

	method read_typed_expr_def () = self#read_enum (function
		| 0 -> TConst (self#read_tconstant ())
		(* TODO: 1 -> TLocal *)
		| 2 ->
			let t1 = self#read_typed_expr () in
			TArray (t1, self#read_typed_expr ())
		| 3 ->
			let t1 = self#read_binop () in
			let t2 = self#read_typed_expr () in
			TBinop (t1, t2, self#read_typed_expr ())
		| 4 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_class_ref () in
			let t3 = self#read_list self#read_type in
			TField (t1, FInstance (t2, t3, self#read_class_field_ref t2))
		| 5 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_class_ref () in
			TField (t1, FStatic (t2, self#read_class_field_ref t2))
		(* TODO: 6 -> TField (e, FAnon (...)) *)
		| 7 ->
			let t1 = self#read_typed_expr () in
			TField (t1, FDynamic (self#read_pstr ()))
		(* TODO: 8 -> TField (e, FClosure (None, ...)) *)
		| 9 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_class_ref () in
			let t3 = self#read_list self#read_type in
			TField (t1, FClosure (Some (t2, t3), self#read_class_field_ref t2))
		| 10 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_enum_ref () in
			TField (t1, FEnum (t2, self#read_enum_field_ref t2))
		| 11 -> TTypeExpr (TClassDecl (self#read_class_ref ()))
		| 12 -> TTypeExpr (TEnumDecl (self#read_enum_ref ()))
		| 13 -> TTypeExpr (TTypeDecl (self#read_typedef_ref ()))
		| 14 -> TTypeExpr (TAbstractDecl (self#read_abstract_ref ()))
		| 15 -> TParenthesis (self#read_typed_expr ())
		| 16 -> TObjectDecl (self#read_list self#read_tobject_field)
		| 17 -> TArrayDecl (self#read_list self#read_typed_expr)
		| 18 ->
			let t1 = self#read_typed_expr () in
			TCall (t1, self#read_list self#read_typed_expr)
		| 19 ->
			let t1 = self#read_class_ref () in
			let t2 = self#read_list self#read_type in
			TNew (t1, t2, self#read_list self#read_typed_expr)
		| 20 ->
			let op, flag = self#read_unop () in
			TUnop (op, flag, self#read_typed_expr ())
		| 21 -> TFunction (self#read_tfunc ())
		| 22 -> TVar (self#read_tvar (), None)
		| 23 ->
			let t1 = self#read_tvar () in
			TVar (t1, Some (self#read_typed_expr ()))
		| 24 -> TBlock (self#read_list self#read_typed_expr)
		| 25 ->
			let t1 = self#read_tvar () in
			let t2 = self#read_typed_expr () in
			TFor (t1, t2, self#read_typed_expr ())
		| 26 ->
			let t1 = self#read_typed_expr () in
			TIf (t1, self#read_typed_expr (), None)
		| 27 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_typed_expr () in
			TIf (t1, t2, Some (self#read_typed_expr ()))
		| 28 ->
			let t1 = self#read_typed_expr () in
			TWhile (t1, self#read_typed_expr (), NormalWhile)
		| 29 ->
			let t1 = self#read_typed_expr () in
			TWhile (t1, self#read_typed_expr (), DoWhile)
		| 30 ->
			let t1 = self#read_typed_expr () in
			TSwitch (t1, self#read_list self#read_tcase, None)
		| 31 ->
			let t1 = self#read_typed_expr () in
			let t2 = self#read_list self#read_tcase in
			TSwitch (t1, t2, Some (self#read_typed_expr ()))
		| 32 ->
			let t1 = self#read_typed_expr () in
			TTry (t1, [self#read_tcatch ()])
		| 33 ->
			let t1 = self#read_typed_expr () in
			TTry (t1, self#read_list self#read_tcatch)
		| 34 -> TReturn None
		| 35 -> TReturn (Some (self#read_typed_expr ()))
		| 36 -> TBreak
		| 37 -> TContinue
		| 38 -> TThrow (self#read_typed_expr ())
		| 39 -> TCast (self#read_typed_expr (), None)
		| 40 ->
			let t1 = self#read_typed_expr () in
			TCast (t1, Some (TClassDecl (self#read_class_ref ())))
		| 41 ->
			let t1 = self#read_typed_expr () in
			TCast (t1, Some (TEnumDecl (self#read_enum_ref ())))
		| 42 ->
			let t1 = self#read_typed_expr () in
			TCast (t1, Some (TTypeDecl (self#read_typedef_ref ())))
		| 43 ->
			let t1 = self#read_typed_expr () in
			TCast (t1, Some (TAbstractDecl (self#read_abstract_ref ())))
		| 44 ->
			let t1 = self#read_metadata_entry () in
			TMeta (t1, self#read_typed_expr ())
		| 45 ->
			let t1 = self#read_typed_expr () in
			let t = (match follow t1.etype with TEnum (t, _) -> t | _ -> assert false) in
			let t2 = self#read_enum_field_ref t in
			TEnumParameter (t1, t2, self#read_uleb128 ())
		| 46 -> TEnumIndex (self#read_typed_expr ())
		| 47 -> TIdent (self#read_pstr ())
		| _ -> raise (HxbReadFailure "read_typed_expr_def"))

	method read_tobject_field () =
		let t1 = self#read_pstr () in
		let t2 = self#read_pos () in
		let t3 = (if (self#read_bool ()) then DoubleQuotes else NoQuotes) in
		(t1, t2, t3), (self#read_typed_expr ())

	method read_tcase () =
		let t1 = self#read_list self#read_typed_expr in
		t1, (self#read_typed_expr ())

	method read_tcatch () =
		let t1 = self#read_tvar () in
		t1, (self#read_typed_expr ())

	method read_typed_expr () =
		let eexpr = self#read_typed_expr_def () in
		let etype = self#read_type () in
		let epos = self#read_pos () in
		{eexpr; etype; epos}

	method read_base_type res =
		res.mt_doc <- self#read_doc ();
		res.mt_meta <- self#read_list self#read_metadata_entry;
		res.mt_params <- self#read_type_params ();
		res.mt_using <- self#read_list self#read_class_using

	method read_class_using () =
		let t1 = self#read_class_ref () in
		t1, (self#read_pos ())

	method read_class_field t res =
		res.cf_type <- self#read_type ();
		res.cf_doc <- self#read_doc ();
		res.cf_meta <- self#read_list self#read_metadata_entry;
		res.cf_kind <- self#read_enum (function
			| 0 -> Method MethNormal
			| 1 -> Method MethInline
			| 2 -> Method MethDynamic
			| 3 -> Method MethMacro
			| v when (v >= 10) && (v <= 234) ->
				let v = v - 10 in
				let r = v / 15 in
				let w = v mod 15 in
				let sub_access = (function
					| 0 -> AccNormal
					| 1 -> AccNo
					| 2 -> AccNever
					| 3 -> AccCtor
					| 4 -> AccResolve
					| 5 -> AccCall
					| 6 -> AccInline
					| 7 ->
						let t1 = self#read_pstr () in
						AccRequire (t1, self#read_nullable self#read_pstr)
					| _ -> raise (HxbReadFailure "read_typed_expr_def cf_kind")) in
				let v_read = sub_access r in
				let v_write = sub_access w in
				Var {v_read; v_write}
			| _ -> raise (HxbReadFailure "read_typed_expr_def cf_kind"));
		res.cf_params <- self#read_type_params ();
		res.cf_expr <- self#read_nullable self#read_typed_expr;
		res.cf_expr_unoptimized <- self#read_nullable self#read_tfunc;
		res.cf_overloads <- self#read_list (fun () -> self#read_class_field_ref t);
		let cf_flags_public, cf_flags_extern, cf_flags_final, cf_flags_overridden, cf_flags_modifies_this = self#read_bools5 () in
		let cf_flags = ref 0 in
		if cf_flags_public then cf_flags := set_flag !cf_flags (int_of_class_field_flag CfPublic);
		if cf_flags_extern then cf_flags := set_flag !cf_flags (int_of_class_field_flag CfExtern);
		if cf_flags_final then cf_flags := set_flag !cf_flags (int_of_class_field_flag CfFinal);
		if cf_flags_overridden then cf_flags := set_flag !cf_flags (int_of_class_field_flag CfOverridden);
		if cf_flags_modifies_this then cf_flags := set_flag !cf_flags (int_of_class_field_flag CfModifiesThis);
		res.cf_flags <- !cf_flags;
		res

	method read_class_type res (statics, fields) =
		self#read_base_type (t_infos (TClassDecl res));
		res.cl_kind <- self#read_enum (function
			| 0 -> KNormal
			| 1 -> KTypeParameter (self#read_list self#read_type)
			| 2 -> KExpr (self#read_expr ())
			| 3 -> KGeneric
			| 4 ->
				let cl, params = self#read_param_class_type () in
				KGenericInstance (cl, params)
			| 5 -> KMacroType
			| 6 -> KGenericBuild (self#read_list self#read_field)
			| 7 -> KAbstractImpl (self#read_abstract_ref ())
			| _ -> raise (HxbReadFailure "read_class_type cl_kind"));
		let cl_extern, cl_final, cl_interface = self#read_bools3 () in
		res.cl_extern <- cl_extern;
		res.cl_final <- cl_final;
		res.cl_interface <- cl_interface;
		res.cl_super <- self#read_nullable self#read_param_class_type;
		res.cl_implements <- self#read_list self#read_param_class_type;
		res.cl_ordered_fields <- List.map (fun name -> self#read_class_field res (PMap.find name res.cl_fields)) fields;
		res.cl_ordered_statics <- List.map (fun name -> self#read_class_field res (PMap.find name res.cl_statics)) statics;
		res.cl_dynamic <- self#read_nullable self#read_type;
		res.cl_array_access <- self#read_nullable self#read_type;
		res.cl_constructor <- self#read_nullable (fun () -> self#read_class_field_ref res);
		res.cl_init <- self#read_nullable self#read_typed_expr;
		res.cl_overrides <- self#read_list (fun () -> self#read_class_field_ref res);
		res.cl_descendants <- []

	method read_param_class_type () =
		let t1 = self#read_class_ref () in
		t1, (self#read_list self#read_type)

	method read_enum_field res ef_index =
		res.ef_type <- self#read_type ();
		res.ef_doc <- self#read_doc ();
		res.ef_params <- self#read_type_params ();
		res.ef_meta <- self#read_list self#read_metadata_entry

	method read_enum_type res fields =
		self#read_base_type (t_infos (TEnumDecl res));
		self#read_def_type res.e_type;
		res.e_extern <- self#read_bool ();
		List.iteri (fun index name -> self#read_enum_field (PMap.find name res.e_constrs) index) fields;
		res.e_names <- fields

	method read_abstract_type res =
		self#read_base_type (t_infos (TAbstractDecl res));
		res.a_impl <- self#read_nullable self#read_class_ref;
		res.a_ops <- self#read_list (fun () -> self#read_abstract_binop res);
		res.a_unops <- self#read_list (fun () -> self#read_abstract_unop res);
		res.a_this <- self#read_type ();
		res.a_from <- self#read_list self#read_type;
		res.a_from_field <- self#read_list (fun () -> self#read_abstract_from_to res);
		res.a_to <- self#read_list self#read_type;
		res.a_to_field <- self#read_list (fun () -> self#read_abstract_from_to res);
		res.a_array <- self#read_list (fun () -> self#read_class_field_ref (Option.get res.a_impl));
		res.a_read <- self#read_nullable (fun () -> self#read_class_field_ref (Option.get res.a_impl));
		res.a_write <- self#read_nullable (fun () -> self#read_class_field_ref (Option.get res.a_impl))

	method read_abstract_binop t =
		let t1 = self#read_binop () in
		t1, (self#read_class_field_ref (Option.get t.a_impl))

	method read_abstract_unop t =
		let op, flag = self#read_unop () in
		op, flag, (self#read_class_field_ref (Option.get t.a_impl))

	method read_abstract_from_to t =
		let t1 = self#read_type () in
		t1, (self#read_class_field_ref (Option.get t.a_impl))

	method read_def_type res =
		self#read_base_type (t_infos (TTypeDecl res));
		res.t_type <- self#read_type ()

	(* Stub types and fields created before the real type is decoded *)

	method stub_base (name, pos, name_pos, priv) =
		let current_module = Option.get current_module in
		let mt_path = (if priv then
				fst current_module.m_path @ ["_" ^ snd current_module.m_path]
			else
				fst current_module.m_path), name in
		let mt_module = current_module in
		let mt_pos = pos in
		let mt_name_pos = name_pos in
		let mt_private = priv in
		let mt_doc = None in
		let mt_meta = [] in
		let mt_params = [] in
		let mt_using = [] in
		{mt_module; mt_path; mt_pos; mt_name_pos; mt_private; mt_doc; mt_meta; mt_params; mt_using}

	method stub_class (name, pos, name_pos, priv) =
		let current_module = Option.get current_module in
		let path = (if priv then
				fst current_module.m_path @ ["_" ^ snd current_module.m_path]
			else
				fst current_module.m_path), name in
		let cl = mk_class current_module path pos name_pos in
		cl.cl_private <- priv;
		cl

	method stub_class_field t is_static (cf_name, cf_pos, cf_name_pos) =
		let cf_type = t_dynamic in
		let cf_doc = None in
		let cf_meta = [] in
		let cf_kind = Var {v_read = AccNormal; v_write = AccNormal} in
		let cf_params = [] in
		let cf_expr = None in
		let cf_expr_unoptimized = None in
		let cf_overloads = [] in
		let cf_flags = 0 in
		let cf = {
			cf_name; cf_pos; cf_name_pos; cf_type; cf_doc; cf_meta; cf_kind;
			cf_params; cf_expr; cf_expr_unoptimized; cf_overloads; cf_flags
		} in
		(* only add to lookup maps, since external references don't use cl_ordered_* *)
		if is_static then
			t.cl_statics <- PMap.add cf_name cf t.cl_statics
		else
			t.cl_fields <- PMap.add cf_name cf t.cl_fields

	method stub_enum ft =
		let mt = self#stub_base ft in
		let e_type = self#stub_typedef ft in
		let e_extern  = false in
		let e_constrs = PMap.empty in
		let e_names = [] in
		{
			e_module = mt.mt_module; e_path = mt.mt_path; e_pos = mt.mt_pos;
			e_name_pos = mt.mt_name_pos; e_private = mt.mt_private; e_doc = mt.mt_doc;
			e_meta = mt.mt_meta; e_params = mt.mt_params; e_using = mt.mt_using;

			e_type; e_extern; e_constrs; e_names
		}

	method stub_enum_field t ef_index (ef_name, ef_pos, ef_name_pos) =
		let ef_type = t_dynamic in
		let ef_doc = None in
		let ef_params = [] in
		let ef_meta = [] in
		let ef = {ef_name; ef_type; ef_pos; ef_name_pos; ef_doc; ef_index; ef_params; ef_meta} in
		(* only add to lookup map, since external references don't use e_names *)
		t.e_constrs <- PMap.add ef_name ef t.e_constrs

	method stub_abstract ft =
		let mt = self#stub_base ft in
		let a_ops = [] in
		let a_unops = [] in
		let a_impl = None in
		let a_this = t_dynamic in
		let a_from = [] in
		let a_from_field = [] in
		let a_to = [] in
		let a_to_field = [] in
		let a_array = [] in
		let a_read = None in
		let a_write = None in
		{
			a_module = mt.mt_module; a_path = mt.mt_path; a_pos = mt.mt_pos;
			a_name_pos = mt.mt_name_pos; a_private = mt.mt_private; a_doc = mt.mt_doc;
			a_meta = mt.mt_meta; a_params = mt.mt_params; a_using = mt.mt_using;

			a_ops; a_unops; a_impl; a_this; a_from; a_from_field; a_to; a_to_field; a_array; a_read; a_write
		}

	method stub_typedef ft =
		let mt = self#stub_base ft in
		let t_type = t_dynamic in
		{
			t_module = mt.mt_module; t_path = mt.mt_path; t_pos = mt.mt_pos;
			t_name_pos = mt.mt_name_pos; t_private = mt.mt_private; t_doc = mt.mt_doc;
			t_meta = mt.mt_meta; t_params = mt.mt_params; t_using = mt.mt_using;

			t_type
		}

	(* File structure *)

	method read_chunk () =
		let chk_size = Int32.to_int (self#read_u32 ()) in
		let chk_id = Bytes.to_string (self#read_str_raw 4) in
		let chk_data = self#read_str_raw chk_size in
		let chk_checksum = self#read_u32 () in
		(* TODO: verify checksum *)
		{chk_id; chk_size; chk_data; chk_checksum}

	method read_header () =
		let config_store_positions = self#read_bool () in
		let m_path = self#read_upath () in
		last_header <- Some {config_store_positions; module_path = m_path};
		let m_file = self#read_str () in
		let m_sign = Bytes.unsafe_to_string (self#read_str_raw 16) in
		let m_inline_calls = self#read_list (fun () ->
			let t1 = self#read_pos () in
			t1, (self#read_pos ())
		) in
		let m_type_hints = [] in
		let m_check_policy = self#read_list (fun () -> self#read_enum HxbEnums.ModuleCheckPolicy.from_int) in
		let m_time = self#read_f64 () in
		let m_dirty = None in (* TODO *)
		let m_added = self#read_leb128 () in
		let m_mark = self#read_leb128 () in
		let m_deps = PMap.empty in (* TODO *)
		let m_processed = self#read_leb128 () in
		let m_kind = self#read_enum HxbEnums.ModuleKind.from_int in
		let m_binded_res = self#read_pmap (fun () ->
			let t1 = self#read_str () in
			t1, (self#read_str ())
		) in
		let m_if_feature = [] in
		let m_features = self#read_hashtbl (fun () ->
			let t1 = self#read_str () in
			t1, (self#read_bool ())
		) in
		current_module <- Some {
			m_id = 0;
			m_path = m_path;
			m_types = [];
			m_extra = {
				m_file; m_sign;
				m_display = {
					m_inline_calls;
					m_type_hints
				};
				m_check_policy;
				m_time; m_dirty; m_added; m_mark; m_deps; m_processed;
				m_kind; m_binded_res; m_if_feature; m_features;
			}
		}

	method read_string_pool () =
		let data = self#read_arr self#read_str in
		last_string_pool <- Some {data}

	method read_doc_pool () =
		let data = self#read_arr self#read_str in
		last_doc_pool <- Some {data}

	method read_type_list () =
		let external_classes = self#read_arr self#read_path in
		let external_enums = self#read_arr self#read_path in
		let external_abstracts = self#read_arr self#read_path in
		let external_typedefs = self#read_arr self#read_path in
		let internal_classes = self#read_arr self#read_forward_type in
		let internal_enums = self#read_arr self#read_forward_type in
		let internal_abstracts = self#read_arr self#read_forward_type in
		let internal_typedefs = self#read_arr self#read_forward_type in
		built_classes <- Some (Array.map self#stub_class internal_classes);
		built_enums <- Some (Array.map self#stub_enum internal_enums);
		built_abstracts <- Some (Array.map self#stub_abstract internal_abstracts);
		built_typedefs <- Some (Array.map self#stub_typedef internal_typedefs);
		last_type_list <- Some {
			external_classes; external_enums; external_abstracts; external_typedefs;
			internal_classes; internal_enums; internal_abstracts; internal_typedefs
		}

	method read_field_list () =
		let class_fields = Array.map (fun t ->
			let statics = self#read_list self#read_forward_field in
			let fields = self#read_list self#read_forward_field in
			List.iter (fun f -> self#stub_class_field t true f) statics;
			List.iter (fun f -> self#stub_class_field t false f) fields;
			(List.map (fun (name, _, _) -> name) statics), (List.map (fun (name, _, _) -> name) fields)
		) (Option.get built_classes) in
		let enum_fields = Array.map (fun t ->
			let constrs = self#read_list self#read_forward_field in
			List.iteri (fun index f -> self#stub_enum_field t index f) constrs;
			List.map (fun (name, _, _) -> name) constrs
		) (Option.get built_enums) in
		last_field_list <- Some {class_fields; enum_fields}

	method read_module_extra () =
		let current_module = Option.get current_module in
		current_module.m_extra.m_display.m_type_hints <- self#read_list (fun () ->
			let t1 = self#read_pos () in
			t1, (self#read_type ())
		);
		current_module.m_extra.m_if_feature <- self#read_list (fun () ->
			let t1 = self#read_str () in
			let t2 = self#read_class_ref () in
			let t3 = self#read_class_field_ref t2 in
			let t4 = self#read_bool () in
			(t1, (t2, t3, t4))
		)

	method read_type_declarations () =
		Array.iter2 self#read_class_type (Option.get built_classes) (Option.get last_field_list).class_fields;
		Array.iter2 self#read_enum_type (Option.get built_enums) (Option.get last_field_list).enum_fields;
		Array.iter self#read_abstract_type (Option.get built_abstracts);
		Array.iter self#read_def_type (Option.get built_typedefs);
		let m_types = ref [] in
		m_types := Array.fold_left (fun types t -> (TClassDecl t) :: types) !m_types (Option.get built_classes);
		m_types := Array.fold_left (fun types t -> (TEnumDecl t) :: types) !m_types (Option.get built_enums);
		m_types := Array.fold_left (fun types t -> (TAbstractDecl t) :: types) !m_types (Option.get built_abstracts);
		m_types := Array.fold_left (fun types t -> (TTypeDecl t) :: types) !m_types (Option.get built_typedefs);
		(Option.get current_module).m_types <- !m_types

	method process_chunk chunk f =
		last_file <- "";
		last_delta <- 0;
		ch <- IO.input_bytes chunk.chk_data;
		f ()

	method process_chunks pass =
		match chunks with
			| Some (header :: rest) ->
				if header.chk_id <> "HHDR" then
					raise (HxbReadFailure "first chunk should be a header");
				self#process_chunk header self#read_header;
				List.iter (fun chunk -> match chunk.chk_id with
					| "HHDR" -> raise (HxbReadFailure "duplicate header")
					| "HEND" -> ()
					(* pass 0: process string and doc pools *)
					| "STRI" -> if pass = 0 then self#process_chunk chunk self#read_string_pool
					| "dOCS" -> if pass = 0 then self#process_chunk chunk self#read_doc_pool
					(* pass 1: process forward declarations *)
					| "TYPL" -> if pass = 1 then self#process_chunk chunk self#read_type_list
					| "FLDL" -> if pass = 1 then self#process_chunk chunk self#read_field_list
					| "xTRA" -> if pass = 1 then self#process_chunk chunk self#read_module_extra
					(* pass 2: process typed AST *)
					| "TYPE" -> if pass = 2 then self#process_chunk chunk self#read_type_declarations
					| _ -> raise (HxbReadFailure "unknown chunk") (* TODO: skip if ancillary *)
				) rest
		| _ -> assert false

	method read_hxb1 () =
		if (Bytes.to_string (self#read_str_raw 4)) <> "hxb1" then
			raise (HxbReadFailure "magic");
		let rec loop () =
			let chunk = self#read_chunk () in
			if chunk.chk_id = "HEND" then
				[chunk]
			else
				chunk :: (loop ())
		in
		chunks <- Some (loop ());
		self#process_chunks 0;
		self#process_chunks 1

	method read_hxb2 () =
		self#process_chunks 2;
		Option.get current_module

end
