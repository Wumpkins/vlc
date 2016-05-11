open Ast 
open Sast
(* open Utils *) 
open Exceptions

(* Maps variable name to variable type and value *)
module Variable_Map = Map.Make(String);;
(* Maps function name to return type *)
module Function_Map = Map.Make(String);;

(* For generating names for the device pointers *)
let dev_name_counter = ref 0
(* For generating names for the host pointers *)
let host_name_counter = ref 0
(* For generating names for each ptx map function *)
let map_ptx_name_counter = ref 0
(* For generating names for each c map function *)
let map_c_name_counter = ref 0
(* For generating names for each reduce function *)
let reduce_c_name_counter = ref 0
(* For generating names for ptx reduce function *)
let reduce_ptx_name_counter = ref 0
(* For generating arg names*)
let arg_counter = ref 0
let ptx_return_counter = ref 0

(* For generating register counters for datatypes *)
let signed_int_counter = ref 1
let signed_float_counter = ref 1
let predicate_counter = ref 1
let block_counter = ref 1
(*-----------------------------------Generates Symbols Based on Counters-----------------------------------*)
let generate_device_pointer_name () = 
    let name = "dev_ptr" ^ (string_of_int !dev_name_counter) in 
    incr dev_name_counter; 
    name

let generate_host_pointer_name () = 
    let name = "host_ptr" ^ (string_of_int !host_name_counter) in 
    incr host_name_counter; 
    name

let generate_map_c_function_name () = 
    let name = "map_c" ^ (string_of_int !map_c_name_counter) in 
    incr map_c_name_counter; 
    name

let generate_map_ptx_function_name () = 
    let name = "map_ptx" ^(string_of_int !map_ptx_name_counter) in 
    incr map_ptx_name_counter; 
    name

let generate_reduce_c_function_name () = 
    let name = "red_c" ^ (string_of_int !reduce_c_name_counter) in 
    incr reduce_c_name_counter;
    name
let generate_reduce_ptx_function_name () = 
    let name = "red_ptx" ^ (string_of_int !reduce_ptx_name_counter) in 
    incr reduce_ptx_name_counter;
    name

let generate_arg_name () = 
    let name = "arg" ^ (string_of_int !arg_counter) in 
    incr arg_counter;
    name
let generate_ptx_return_name () = 
    let name = "func_ret" ^ (string_of_int !ptx_return_counter) in 
    incr arg_counter;
    name
(*-----------------------------------Types for Semantic Analysis-----------------------------------*)
(* Three types of functions *)
type cuda_function_type  = 
  | Kernel_Global
  | Kernel_Device 
  | Host 

(* Stores information about a function *)
type function_info = {
  (* Host, kernel_device, kernel_global *)
  function_type                   : cuda_function_type; 
  (* Name of function *)
  function_name                   : Ast.identifier;
  (* Function return type and arguments *)
  function_return_type            : Ast.variable_type;
  function_args                   : (Ast.variable_type) list;
  (* Functions that are called within this function - needs to be specifically noted for gpu and ptx functions *)
  dependent_functions             : Ast.identifier list;
  (* Unknown ,possibly constant variables -> for kernel_device and kernel_global *)
  unknown_variables               : Ast.identifier list;
}

type variable_info = {
  vtype : Ast.variable_type;
  register_number :int;
}
 
(* Stores information about the environment *)
type environment = {
  (* Variables that have been declared in the environment - stores variable name, variable type *)
  variable_scope_stack                              : variable_info Variable_Map.t list;
  (* List of kernel functions that have been declared in the environment  - info from function_info record *)
  kernel_function_map                               : function_info Function_Map.t;
  (* List of host functions that have been declared in the environment - info from function_info record *)
  host_function_map                                 : function_info Function_Map.t;
  (* Bool specifying whether environment is being evaluated on the gpu *)
  is_gpu_env                                        : bool;
  (*List of functions for higher order functions *)
  hof_c_function_list                               : Sast.c_higher_order_fdecl list;
  hof_ptx_function_list                             : Sast.ptx_higher_order_fdecl list;
}

(*-----------------------------------Helper functions to check variables and functions in the environment -----------------------------------*)

let builtin_functions = ["print";]


(* Checks if function is a builtin function *)
(* Used to check function declarations to make sure they aren't declaring anything with the same name *)
let is_builtin_function id =
  List.exists (fun function_name -> function_name = id) builtin_functions


(* Creates a function_info record with information *)
let create_function_info ftype rtype args df uv name = {
  function_type                   = ftype;
  function_name                   = Identifier(name);
  function_return_type            = rtype;
  function_args                   = args;
  dependent_functions             = df;
  unknown_variables               = uv;
}


(* Function for adding initializing host function map, adds builtin functions to host function map*)
let init_host_function_map = 
  let fmap = Function_Map.empty in 
  let rec add_functions fmap function_list = 
    match function_list with 
      | [] -> fmap 
      | f_info::tl -> add_functions (Function_Map.add (Utils.idtos(f_info.function_name)) f_info fmap) tl
  in
  let print_function = {
      function_type = Host;
      function_name = Ast.Identifier("print");
      function_return_type = Ast.Primitive(Ast.Void);
      function_args = [Ast.Primitive(Ast.String)];
      dependent_functions = [];
      unknown_variables = [];
  }
  in
  let random_function = {
      function_type = Host;
      function_name = Ast.Identifier("random");
      function_return_type = Ast.Primitive(Ast.Integer);
      function_args = [];
      dependent_functions = [];
      unknown_variables = [];
  }
in
 (*  let create_built_in_function = (create_function_info Host (Ast.Primitive(Ast.Void)) [] [] []) in 
  let builtin_function_info_structs = List.map create_built_in_function builtin_functions in *)
  add_functions fmap [print_function;random_function]


(* Creates a new environment *)
let init_env = {
  variable_scope_stack        = Variable_Map.empty :: [];
  kernel_function_map         = Function_Map.empty;
  host_function_map           = init_host_function_map;
  is_gpu_env                  = false;
  (* Two lists that stores the new higher order functions we need to add*)
  hof_c_function_list         = [];
  hof_ptx_function_list       = [];
}


(* Updates the environment *)
let update_env vscope_stack kfmap hfmap is_gpu hof_c_list hof_ptx_list= {
  variable_scope_stack        = vscope_stack;
  kernel_function_map         = kfmap;
  host_function_map           = hfmap;
  is_gpu_env                  = is_gpu;
  hof_c_function_list         = hof_c_list;
  hof_ptx_function_list       = hof_ptx_list;
}


(* Pushes a new scope on top of the  variable_scope_stack *)
let push_scope env = 
    update_env (Variable_Map.empty :: env.variable_scope_stack) env.kernel_function_map env.host_function_map env.is_gpu_env env.hof_c_function_list env.hof_ptx_function_list

(* Pops a scope from the top of the variable_scope_stack *)
let pop_scope env = 
    match env.variable_scope_stack with
      | [] -> raise Exceptions.Cannot_pop_empty_variable_scope_stack
      | local_scope :: tail ->
          update_env tail env.kernel_function_map env.host_function_map env.is_gpu_env env.hof_c_function_list env.hof_ptx_function_list

let update_scope updated_scope env = 
    let env = pop_scope env in 
    update_env (updated_scope::env.variable_scope_stack) env.kernel_function_map env.host_function_map env.is_gpu_env env.hof_c_function_list env.hof_ptx_function_list

let update_kernel_fmap f_info env = 
    let new_kfmap = Function_Map.add (Utils.idtos(f_info.function_name)) f_info env.kernel_function_map in
    update_env env.variable_scope_stack new_kfmap env.host_function_map env.is_gpu_env env.hof_c_function_list env.hof_ptx_function_list

let update_host_fmap f_info env = 
    let new_hfmap = Function_Map.add (Utils.idtos(f_info.function_name)) f_info env.host_function_map in
    update_env env.variable_scope_stack env.kernel_function_map new_hfmap env.is_gpu_env env.hof_c_function_list env.hof_ptx_function_list

let update_hof_lists hof_c_fdecl hof_ptx_fdecl env = 
    update_env env.variable_scope_stack env.kernel_function_map env.host_function_map env.is_gpu_env (List.rev(hof_c_fdecl::List.rev(env.hof_c_function_list))) (List.rev(hof_ptx_fdecl::List.rev(env.hof_ptx_function_list))) 


(* Checks if variable has been declared - is valid - in the scope *)
let is_variable_in_scope id env = 
    let rec check_scopes scope_stack = 
      match scope_stack with
        | [] -> false
        | [scope] ->
          if env.is_gpu_env then false 
          else (Variable_Map.mem id scope)
        | scope :: larger_scopes -> 
          if (Variable_Map.mem id scope) then true
          else check_scopes larger_scopes
      in check_scopes env.variable_scope_stack


(* Searches variable in scope for CUDA C and returns its type *)
let get_variable_type id env = 
  let rec check_scopes scope_stack = 
    match scope_stack with 
      | [] -> raise (Exceptions.Variable_not_found_in_scope  ( id))
      | scope::larger_scopes -> 
          if Variable_Map.mem id scope then 
            (Variable_Map.find id scope).vtype
          else
            check_scopes larger_scopes
  in check_scopes env.variable_scope_stack

let get_variable_info id env = 
  let rec check_scopes scope_stack = 
    match scope_stack with 
      | [] -> raise (Exceptions.Variable_not_found_in_scope  ( id))
      | scope::larger_scopes -> 
          if Variable_Map.mem id scope then 
            Variable_Map.find id scope
          else
            check_scopes larger_scopes
  in check_scopes env.variable_scope_stack

(* Helper function that returns checks types are the same *)
let same_types t1 t2 = (t1 = t2)

(* Checks if function is valid in the environment *)
let is_function_in_scope id env = 
  if env.is_gpu_env = true then (Function_Map.mem id env.kernel_function_map)
  else (Function_Map.mem id env.host_function_map) || (Function_Map.mem id env.kernel_function_map)


(* Searches for function called in function call and returns information about the function *)
let get_function_info id env = 
    if env.is_gpu_env = true then
        (if(Function_Map.mem id env.kernel_function_map) then
            (Function_Map.find id env.kernel_function_map)
        else raise (Exceptions.Function_not_defined (id)))
    else
        (if (Function_Map.mem id env.host_function_map) then 
            (Function_Map.find id env.host_function_map)
        else if (Function_Map.mem id env.kernel_function_map) then 
            (Function_Map.find id env.kernel_function_map)
        else raise (Exceptions.Function_not_defined (id)))

(* ----------------------------------- Functions for Checking Ast -----------------------------------*)
(* Checks a variable declaration and initialization to ensure variable hasn't already been declared *)
let check_already_declared id env = 
  if ((is_variable_in_scope id env) = true) then true else false


(* Note: for host only! Checks that a variable in assignments and expressions have been declared*)
let check_var_is_declared id env = 
  if (is_variable_in_scope id env)= false then (raise Exceptions.Variable_not_declared)

(* Helper function that performs type inference for expressions *)
let rec infer_type expression env=
  let f type1 type2 =
    match type1 with
      | Some(t) -> (if t = type2 then Some(t)
                    else raise (Exceptions.Type_mismatch "wrong types"))
      | None -> Some(type2) in
  let match_type expression_list =
    let a = List.fold_left f None expression_list in
      match a with
        | Some(t) -> t
        | None -> raise Exceptions.Empty_array_expression_list in
  match expression with
    | Ast.String_Literal(_) -> Ast.Primitive(Ast.String)
    | Ast.Integer_Literal(_) -> Ast.Primitive(Ast.Integer)
    | Ast.Floating_Point_Literal(_) -> Ast.Primitive(Ast.Float)
    | Ast.Boolean_Literal(_) -> Ast.Primitive(Ast.Boolean)
    | Ast.Array_Literal(expr_list) ->
       let f expression = infer_type expression env in
      Ast.Array(match_type (List.map f expr_list),(List.length expr_list))
    | Ast.Identifier_Literal(id) -> 
        if(check_already_declared (Utils.idtos id) env) = false then raise (Exceptions.Variable_not_found_in_scope ( Utils.idtos id)) 
        else (get_variable_type (Utils.idtos id) env)
    | Ast.Binop(e1,op,e2) -> 
        (match op with 
          | Ast.And | Ast.Or | Ast.Xor -> Ast.Primitive(Ast.Boolean)
          | _ -> if (same_types (infer_type e1 env) (infer_type e2 env)) = true then infer_type e1 env 
                  else (raise (Exceptions.Type_mismatch("Binop types don't match")))
        )
    | Ast.Cast(vtype,e) -> vtype
    | Ast.Unop(e,unop) -> infer_type e env
    | Ast.Array_Accessor(e1,e_list,is_lvalue) -> 
        (* Check e1 is an array *) 
          (match infer_type e1 env with 
            | Ast.Array(t,n) -> ()
            | _ -> (raise (Exceptions.Not_an_array_expression))
          );
        (* Check valid access *)
        let rec get_array_type arr dim_list = 
          match dim_list with
            | [] -> raise Exceptions.Empty_array_access
            | hd::[] -> 
              (match arr with
                | Ast.Array(t,n) -> t
                | _ -> raise Invalid_array_expression
              )
            | hd::tl ->
              ( match arr with 
                | Ast.Array(t,n) -> get_array_type t tl
                | _ -> raise Exceptions.Invalid_array_expression
              )
        in get_array_type (infer_type e1 env) e_list
    | Ast.Ternary(e1,e2,e3) ->
        if(same_types (infer_type e1 env) (infer_type e2 env)) = true then infer_type e1 env else (raise (Exceptions.Type_mismatch("Ternary doesn't return same type")))
    | Ast.Higher_Order_Function_Call(hof) -> 
      let f_info = get_function_info (Utils.idtos hof.kernel_function_name) env in
      let vtype = infer_type (List.hd hof.input_arrays) env in
        let length = match vtype with 
          | Ast.Primitive(p) -> raise Exceptions.Invalid_array_expression
          | Ast.Array(t,n) -> n
        in
      Ast.Array(f_info.function_return_type,length)
    | Ast.Function_Call(id,e_list) -> 
        let f_info = get_function_info (Utils.idtos id) env in
        f_info.function_return_type
    | _ as i-> raise (Exceptions.Cannot_infer_expression_type(Utils.expression_to_string i))


(* Check that array has only one dimension - used for certain operations *)
let is_one_layer_array expression env = 
    match expression with 
    | Ast.Array_Literal(e_list) as array_literal -> 
        let arr = infer_type array_literal env in
          (match arr with
          | Ast.Array(vtype,size) -> if size > 1 then false else true
          | _ -> raise Exceptions.Not_an_array_expression)
    | _ -> raise Exceptions.Not_an_array_expression


(* Helper function that returns a list of dimensions for an array variable type *)
let rec get_array_dimensions vtype dimensions = 
  match vtype with
  | Ast.Array(t,n) -> 
      get_array_dimensions t (List.rev(n::List.rev(dimensions)))
  | Ast.Primitive(p) -> dimensions
(*   | _ -> raise Exceptions.Unknown_variable_type *)




(* ----------------------------------- Functions for converting ast to sast (Also performs advanced checking) -----------------------------------*)


(* Converts a function declaration to a PTX function declaration. This is done in five parts:
    1. Checking to see if the function exists
    1. Adding a new global (map/reduce) function to the kernel function map in environemnt
    2. Adding a new device function (defg) to the kernel function map in environment
    3. Adding a new function to the host function map in environment
    5. Converting fdecl into ptx_fedcl *)
(* TO IMPLEMENT let convert_to_ptx_fdecl fdecl env = (fdecl,env)
    let global_func_info = {
        function_type = Kernel_Global;
        function_name = fdecl.name;
        function_return_type = fdecl.return_type;
        function_args = fdecl.params;
    } :: env.kernel_function_map in
    
    let kernel_func_info = {
        function_type = Kernel_Device;
        function_name = fdecl.name;
        function_return_type = fdecl.return_type;
        function_args = fdecl.params;
    } :: env.kernel_function_map in
    
    let host_func_info = {
        function_type = Host;
        function_name = fdecl.name;
        function_return_type = fdecl.return_type;
        function_args = fdecl.params;
    } :: env.host_function_map in
    
    (fdecl, update_env env.variable_scope_stack, kernel_func_info, host_func_info env.is_gpu_env);
     *)


(* Converts a function declaration to a C function declaration
    1. Check to see if the function is already declared
    2. Update environment to contain the fdecl
    3. Convert fdecl into c_fdecl *)



(* Checks statement order - nothing follows a return , break, or continue in a block*)
let rec good_statement_order stmt_list = 
  match stmt_list with 
    | [] ->true
    | hd ::[] -> true
    | hd :: tl ->
        match hd with 
          | Ast.Return_Void | Ast.Continue | Ast.Break -> false
          | Ast.Return(e)-> false
          | _ -> good_statement_order tl
    
    (* Binop *)
let convert_to_c_binop binop env = 
  match binop with
    | Ast.Add -> Sast.Add,env 
    | Ast.Subtract -> Sast.Subtract,env
    | Ast.Multiply -> Sast.Multiply,env
    | Ast.Divide -> Sast.Divide,env
    | Ast.Modulo -> Sast.Modulo,env
    | Ast.And -> Sast.And,env
    | Ast.Or -> Sast.Or,env
    | Ast.Xor -> Sast.Xor,env
    | Ast.Equal -> Sast.Equal,env
    | Ast.Not_Equal -> Sast.Not_Equal,env
    | Ast.Greater_Than -> Sast.Greater_Than,env
    | Ast.Less_Than -> Sast.Less_Than,env
    | Ast.Greater_Than_Equal -> Sast.Greater_Than_Equal,env
    | Ast.Less_Than_Equal -> Sast.Less_Than_Equal,env
    | Ast.Bitshift_Right -> Sast.Bitshift_Right,env
    | Ast.Bitshift_Left -> Sast.Bitshift_Left,env
    | Ast.Bitwise_Or -> Sast.Bitwise_Or,env
    | Ast.Bitwise_And -> Sast.Bitwise_And,env
    
let convert_to_ptx_binop binop env = 
  match binop with
    | Ast.Add -> Sast.Ptx_Add,env
    | Ast.Subtract -> Sast.Ptx_Subtract,env
    | Ast.Multiply -> Sast.Ptx_Multiply,env
    | Ast.Divide -> Sast.Ptx_Divide,env
    | Ast.Modulo -> Sast.Ptx_Modulo,env
    | Ast.And -> Sast.Ptx_And,env
    | Ast.Or -> Sast.Ptx_Or,env
    | Ast.Xor -> Sast.Ptx_Xor,env
    | Ast.Equal -> Sast.Ptx_Equal,env
    | Ast.Not_Equal -> Sast.Ptx_Not_Equal,env
    | Ast.Greater_Than -> Sast.Ptx_Greater_Than,env
    | Ast.Less_Than -> Sast.Ptx_Less_Than,env
    | Ast.Greater_Than_Equal -> Sast.Ptx_Greater_Than_Equal,env
    | Ast.Less_Than_Equal -> Sast.Ptx_Less_Than_Equal,env
    | Ast.Bitshift_Right -> Sast.Ptx_Bitshift_Right,env
    | Ast.Bitshift_Left -> Sast.Ptx_Bitshift_Left,env
    | Ast.Bitwise_Or -> Sast.Ptx_Bitwise_Or,env
    | Ast.Bitwise_And -> Sast.Ptx_Bitwise_And,env
    

  (* Unop *)
let convert_to_c_unop unop env =
  match unop with
    | Ast.Not -> Sast.Not,env
    | Ast.Negate -> Sast.Negate,env
    | Ast.Plus_Plus -> Sast.Plus_Plus,env
    | Ast.Minus_Minus -> Sast.Minus_Minus,env
    
let convert_to_ptx_unop unop env =
  match unop with
    | Ast.Not -> Sast.Ptx_Not,env
    | Ast.Negate -> Sast.Ptx_Negate,env
    | Ast.Plus_Plus -> Sast.Ptx_Plus_Plus,env
    | Ast.Minus_Minus -> Sast.Ptx_Minus_Minus,env


(* Datatype *)
let convert_to_c_data_type dtype env = 
  match dtype with
      | Ast.Integer -> Sast.Integer,env
      | Ast.Float -> Sast.Float,env
      | Ast.String -> Sast.String,env
      | Ast.Boolean -> Sast.Boolean,env
      | Ast.Void -> Sast.Void,env
      
let convert_to_ptx_data_type dtype env =
  match dtype with
    | Ast.Integer -> Sast.S32,env
    | Ast.Float -> Sast.F32,env
    | Ast.Boolean -> Sast.Pred,env
    | Ast.String -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
    | Ast.Void -> Sast.Ptx_Void,env

    (* Variable Type *)
let rec convert_to_c_variable_type vtype env = 
  match vtype with
      | Ast.Primitive(p) -> 
          let c_p,env = convert_to_c_data_type p env in
          Sast.Primitive(c_p),env
      | Ast.Array(t,n) ->
          let inside = (match t with 
            | Ast.Array(t,n) -> 
                let c_t,env = convert_to_c_variable_type t env in
                Sast.Array(c_t,n)
            | Ast.Primitive(p) -> 
                let c_p,env= convert_to_c_data_type p env in
                Sast.Primitive(c_p)
          ) in
          Sast.Array(inside, n),env

(* TO IMPLEMENT *)
let convert_to_ptx_variable_type vtype env = 
  match vtype with
      | Ast.Primitive(p) -> 
          let p2,env = convert_to_ptx_data_type p env in
          Sast.Ptx_Primitive(p2),env
      | Ast.Array(t,n) -> raise Exceptions.C'est_La_Vie
(*           (match t with 
            | Ast.Array(t,n) -> 
                let c_t,env = convert_to_ptx_variable_type t env in
                Sast.Array(c_t,n),env
            | Ast.Primitive(p) -> 
                let c_p,env= convert_to_ptx_data_type p env in
                Sast.Primitive(c_p),env
          ) *)

(* Variable Declarations *)
let convert_to_c_vdecl vdecl env  = 
    match vdecl with 
      | Ast.Variable_Declaration(vtype,id) ->
          if(check_already_declared (Utils.idtos(id)) env) = true then raise Exceptions.Variable_already_declared
          else
            let v_info = {
              vtype = vtype;
              register_number = 0;
            }
            in
            let new_vmap = Variable_Map.add (Utils.idtos id) v_info (List.hd env.variable_scope_stack) in
            let env = update_scope new_vmap env in
            let c_vtype, env = convert_to_c_variable_type vtype env in
            Sast.Variable_Declaration(c_vtype,id),env

let convert_to_ptx_vdecl vdecl env =
  match vdecl with
    | Ast.Variable_Declaration(vtype,id) ->
        if(check_already_declared (Utils.idtos(id)) env) = true then raise Exceptions.Variable_already_declared
        else
          let regNum = match vtype with
            | Ast.Primitive(Ast.Integer) -> let num = !signed_int_counter in (incr signed_int_counter ; num)
            | Ast.Primitive(Ast.Float) -> let num = !signed_float_counter in (incr signed_float_counter ; num)
            | Ast.Primitive(Ast.Boolean) -> let num = !predicate_counter in (incr predicate_counter ; num)
            | Ast.Primitive(Ast.String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
            | Ast.Primitive(Ast.Void) -> raise Exceptions.Void_type_in_gdecl
            | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_Vie
          in
          let v_info = {
            vtype = vtype;
            register_number = regNum;
          }
          in
          let new_vmap = Variable_Map.add (Utils.idtos id) v_info (List.hd env.variable_scope_stack) in
          update_scope new_vmap env 


let same_types_list type_list = 
  let main_type = (List.hd type_list) in 
    let rec check_each_type main_type type_list =
      (match type_list with
        | [] -> true
        | hd::tl -> 
          if(same_types main_type hd) then (check_each_type main_type tl)
          else raise Exceptions.Array_elements_not_all_same_type
      ) 
    in check_each_type main_type type_list

(* Creates list of sast structs storing information about constants for higher order function *)
let rec get_constants_info constant_list c_constant_list env = 
  match constant_list with 
  | [] -> c_constant_list
  | hd::tl ->
      (match hd with 
        | Ast.Constant(id,e) -> 
            let vtype = infer_type e env in 
            (* Name of constant in defg gpu function*)
            let h_name = Ast.Identifier(generate_host_pointer_name ()) in 
            (* Name of constant when input as an argument *)
            let a_name = Ast.Identifier(generate_arg_name ())in
            let v_type,env = convert_to_c_variable_type vtype env in
            (* Sast.type*)
            let constant_info = {
                variable_type = v_type;
                host_name = h_name;
                arg_name = a_name;
                kernel_name = id;   
            } in get_constants_info tl (List.rev(constant_info::List.rev(c_constant_list))) env
      )
    
(* Creates list of sast structs storing information about info arrays from higher order function *)
let rec get_input_arrays_info input_arrays var_info_list env = 
  match input_arrays with 
    | [] -> var_info_list
    | hd::tl ->
      (
        match infer_type hd env with 
          | Ast.Array(t,n) ->
              let h_name = Ast.Identifier(generate_host_pointer_name ())in
              let k_name = Ast.Identifier(generate_device_pointer_name ())in
              let a_name = Ast.Identifier(generate_arg_name ())in
              let vtype,env = convert_to_c_variable_type( infer_type hd env) env in
              let var_info = {
                  variable_type = vtype;
                  host_name = h_name;
                  kernel_name = k_name;
                  arg_name = a_name;
              } 
            in get_input_arrays_info tl (List.rev(var_info::List.rev(var_info_list))) env
          | _ -> raise Exceptions.Nonarray_argument_passed_into_higher_order_function
      )

(* Creates sast struct storing information about return array from higher order function *)
let get_return_array_info kfunc_id length env = 
  let f_info            = get_function_info kfunc_id env in
  let return_vtype,env  = convert_to_c_variable_type (Ast.Array(f_info.function_return_type,length)) env in
  let h_name            = Ast.Identifier(generate_host_pointer_name ())in
  let k_name            = Ast.Identifier(generate_device_pointer_name ())in
  let a_name            = Ast.Identifier(generate_arg_name ()) in 
  let var_info          =  {
      variable_type     = return_vtype;
      host_name         = h_name;
      kernel_name       = k_name;
      arg_name          = a_name;
  } in
  var_info

(* Main function for creating the C map function (when we see a map function call) *)
let make_hof_c_fdecl hof_call env =  
  let arr_length = 
              let arr = infer_type (List.hd hof_call.input_arrays) env in
              (match arr with 
              | Ast.Array(t,n) -> n
              | _ -> raise Exceptions.Not_an_array_expression)
  in
  match Utils.idtos(hof_call.hof_type) with
    | "map" ->
          let kfunc_name = Ast.Identifier(generate_map_ptx_function_name ()) in
         {
            higher_order_function_type                                          =  Ast.Identifier("map");
            higher_order_function_name                                          =  Ast.Identifier(generate_map_c_function_name ());
            applied_kernel_function                                             =  kfunc_name;
            higher_order_function_constants                                     =  get_constants_info hof_call.constants [] env;
            array_length                                                        =  arr_length;
            input_arrays_info                                                   =  get_input_arrays_info hof_call.input_arrays [] env;
            return_array_info                                                   =  get_return_array_info (Utils.idtos(hof_call.kernel_function_name)) arr_length env;
            called_functions                                                    =  [hof_call.kernel_function_name]
         } 
    | "reduce" -> 
          let kfunc_name = Ast.Identifier(generate_reduce_ptx_function_name ()) in
           {
              higher_order_function_type                                          =  Ast.Identifier("reduce");
              higher_order_function_name                                          =  Ast.Identifier(generate_reduce_c_function_name ());
              applied_kernel_function                                             =  kfunc_name;
              higher_order_function_constants                                     =  get_constants_info hof_call.constants [] env;
              array_length                                                        =  arr_length;
              input_arrays_info                                                   =  get_input_arrays_info hof_call.input_arrays [] env;
              return_array_info                                                   =  get_return_array_info (Utils.idtos(hof_call.kernel_function_name)) arr_length env;
              called_functions                                                    =  [hof_call.kernel_function_name]
           }  
    | _ -> raise (Exceptions.Unknown_higher_order_function_call (Utils.idtos hof_call.hof_type))

(* TO IMPLEMENT 
Converts c_kernel_variable_info to ptx_kernel_variable_info *)
let change_to_ptx_data_type sast_c_dtype = 
    match sast_c_dtype with 
      | Sast.Integer -> S32
      | Sast.Float   -> F32
      | Sast.Boolean -> Pred
      | _ -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL

let rec change_to_ptx_variable_type sast_c_vtype = 
  match sast_c_vtype with 
      | Sast.Primitive(p) -> Ptx_Primitive(change_to_ptx_data_type p)
      | Sast.Array(t,n) -> Ptx_Array(change_to_ptx_variable_type t, n)

let change_to_ptx_kernel_variable ckv_info =
  {
      ptx_variable_type = change_to_ptx_variable_type ckv_info.variable_type;
      ptx_kernel_name   = ckv_info.kernel_name;
  }

let change_to_pdecl k_info  =
  let rec get_dtype d = (match d with
      | Sast.Primitive(p) -> change_to_ptx_data_type p
      | Sast.Array(t,n) -> get_dtype t)
  in 
  let dtype = get_dtype k_info.variable_type in
  {
      ptx_parameter_data_type = dtype;
(*       ptx_parameter_is_pointer:   int;  *) (* 1 if true, 0 if false*)
      ptx_parameter_state_space = Sast.Global;
      (*  ptx_parameter_variable_option:  ptx_variable_option; *)
      ptx_parameter_name = k_info.kernel_name;
  }


(* Creates a ptx_fdecl based on the hof_c_fdecl*)
let make_hof_ptx_fdecl hof_c_fdecl hof env= 
  {
    ptx_higher_order_function_type                      = hof_c_fdecl.higher_order_function_type;
    ptx_higher_order_function_name                      = hof_c_fdecl.applied_kernel_function;
    ptx_applied_kernel_function                         = hof.kernel_function_name;
    ptx_higher_order_function_constants                 = List.map (fun x -> change_to_ptx_kernel_variable x ) hof_c_fdecl.higher_order_function_constants;
    ptx_array_length                                    = hof_c_fdecl.array_length;
    ptx_input_arrays_info                               = List.map change_to_pdecl hof_c_fdecl.input_arrays_info;
    ptx_return_array_info                               = change_to_pdecl hof_c_fdecl.return_array_info;
    ptx_called_functions                                = [hof.kernel_function_name]
  }


(* TO IMPLEMENT  let convert_to_ptx_pdecl e = 
    match e with 
      |  *)
  

(* In CUDA, is just 
        int tid = blockDim.x * blockIdx.x + threadIdx.x;
        if (tid < n_el) 
          C[tid] = function(A[tid], B[tid] ...)
      *)
      (*  Second to last param is result array
          Last param is array length*)
(*  let make_map_ptx_fdecl c_map_fdecl = 
    let input_params = List.map convert_to_ptx_pdecl c_map_fdecl.input_arrays_info in
    let result_param = convert_to_ptx_pdecl c_map_fdecl return_type_array_info in
    let length = Sast.Constant_Int(c_map_fdecl.array_length) in
    let params = input_params@[result_param;length] in 
      let make_global_map_body params = 
          
      in
    let body = make_global_map_body params 
    in
    {
      ptx_fdecl_type    = Sast.Global;
      ptx_fdecl_name    = generate_map_ptx_function_name;
      ptx_fdecl_params  = params;
      ptx_fdecl_body    = body;
    } *)
let rec get_types args types env = 
  match args with
    | [] -> types
    | hd::tl -> get_types tl (List.rev((infer_type hd env)::List.rev types)) env     

let rec add_lists list_lists newlist= 
  match list_lists with
  | [] -> newlist
  | hd::tl -> add_lists tl (newlist @ hd)

let rec convert_to_c_expression e env = 
  let rec flatten_array e flattened_array env = 
    (match e with 
      | Ast.Array_Literal(e_list) -> 
            (match List.hd e_list with 
              | Ast.Array_Literal(e1_list) -> 
                  let list_of_flattened_arrays = List.map (fun x-> flatten_array x [] env) e_list in
                  add_lists list_of_flattened_arrays []
              | _ ->  flattened_array @ (List.map (fun x -> fst(convert_to_c_expression x env)) e_list)
            )
      | _ -> raise Exceptions.Not_an_array_expression
    )
  in
    match e with 
      | Ast.Function_Call(id,e_list) ->
        (* Check that function exists in environment *)
         if (is_function_in_scope (Utils.idtos id) env) = false then (raise (Exceptions.Function_not_defined (Utils.idtos id)));
        (* Check that function arguments match that of function declaration *)
        let f_info = (get_function_info (Utils.idtos id) env) in
        let f_arg_types = f_info.function_args in 
              let check_args expected_arg_types f_args =  
              List.map2 same_types expected_arg_types f_args in
        ignore(check_args f_arg_types (get_types e_list [] env));
        (* Convert *)
        let c_e_list = List.map (fun x -> fst(convert_to_c_expression x env)) e_list 
        in Sast.Function_Call(id,c_e_list),env
      | Ast.String_Literal(s) -> Sast.String_Literal(s),env
      | Ast.Integer_Literal(i) -> Sast.Integer_Literal(i),env
      | Ast.Boolean_Literal(b) -> Sast.Boolean_Literal(b),env
      | Ast.Floating_Point_Literal(f) -> Sast.Floating_Point_Literal(f),env
      | Ast.Array_Literal(e_list) -> 
          (* Check all elements of the array are the same type *)
          let type_list = List.map (fun x -> infer_type x env) e_list in 
          ignore(same_types_list type_list);
          (* Get array dimensions and pass to sast *)
          let arr = Ast.Array(infer_type (List.hd e_list) env ,List.length e_list) in
          let array_dim = get_array_dimensions arr [] in
          (* Convert *)
          let c_e_list = flatten_array e [] env in
          Sast.Array_Literal(c_e_list,array_dim),env
      | Ast.Identifier_Literal(id) -> 
          if(check_already_declared (Utils.idtos id) env) = false then raise (Exceptions.Variable_not_found_in_scope ( Utils.idtos id))
          else Sast.Identifier_Literal(id),env
      | Ast.Cast(vtype, e) -> 
          let c_vtype,env = convert_to_c_variable_type vtype env in
          let c_e,env = convert_to_c_expression e env in
          Sast.Cast(c_vtype,c_e),env
      | Ast.Unop(e,op) ->
          (match op with 
            | Ast.Not -> 
              if((infer_type e env)= Ast.Primitive(Ast.Boolean)) = false then raise (Exceptions.Type_mismatch("Must use boolean expression with boolean unop"))
              else
                let c_e,env = convert_to_c_expression e env in 
                let c_op,env = convert_to_c_unop op env in
                Sast.Unop(c_e,c_op),env
            | _ -> 
              if((infer_type e env) = (Ast.Primitive (Ast.String))) then raise (Exceptions.Cannot_perform_operation_on_string (Utils.unary_operator_to_string op))
              else
                let c_e,env = convert_to_c_expression e env in 
                let c_op,env = convert_to_c_unop op env in
                Sast.Unop(c_e,c_op),env
          )
      | Ast.Ternary(e1,e2,e3) ->
        (*Check e1 and e3 match*)
        if(same_types (infer_type e1 env) (infer_type e3 env)) = false then raise (Exceptions.Type_mismatch("Ternary expression don't match"))
        else
          (*Check e2 is boolean*)
          if(same_types (infer_type e2 env) (Ast.Primitive(Ast.Boolean))) = false then (raise (Exceptions.Conditional_must_be_a_boolean))
          else
            let c_e1,env = convert_to_c_expression e1 env in 
            let c_e2,env = convert_to_c_expression e2 env in 
            let c_e3,env = convert_to_c_expression e3 env in 
            Sast.Ternary(c_e1,c_e2,c_e3),env
      | Ast.Array_Accessor(e,e_list,is_lvalue) ->
        (* Check e is an array *)
          (match infer_type e env with 
            | Ast.Array(t,n) -> ()
            | _ -> raise Exceptions.Not_an_array_expression);
          (* Check that e_list can access a*)
          ignore(List.map (fun x -> same_types (infer_type x env) (Ast.Primitive(Ast.Integer))) e_list);
          (* Convert *)
          let c_e,env = convert_to_c_expression e env  in
          let c_e_list = List.map (fun x -> fst(convert_to_c_expression x env)) e_list in
          let array_type = infer_type e env in
          let array_dims = get_array_dimensions array_type [] in
          let array_access = ((List.length array_dims) > (List.length e_list)) in
          Sast.Array_Accessor(c_e,c_e_list,is_lvalue,array_access),env
      | Ast.Binop(e1,op,e2) -> 
          (* Check that expressions match *)
          if((same_types (infer_type e1 env) (infer_type e2 env)) = false) then raise (Exceptions.Type_mismatch "Binop doesn't match")
          else
            (match op with 
              | Ast.And | Ast.Or | Ast.Xor -> 
                (* Check that type is boolean if using boolean operator *)
                ignore(same_types (infer_type e1 env) (Ast.Primitive(Ast.Boolean)));
                  let c_e1,env = convert_to_c_expression e1 env in
                  let c_op,env = convert_to_c_binop op env in
                  let c_e2,env = convert_to_c_expression e2 env in
                  Sast.Binop(c_e1,c_op,c_e2),env
              | _ -> 
                (* Check if type is string, array *)
                  (match (infer_type e1 env) with
                    | Ast.Primitive(t) -> if t = Ast.String then raise (Exceptions.Cannot_perform_operation_on_string (Utils.binary_operator_to_string op)) else ()
                    | Ast.Array(t,n) -> raise (Exceptions.Cannot_perform_operation_on_array (Utils.binary_operator_to_string op))
                  );
                  let c_e1,env = convert_to_c_expression e1 env in
                  let c_op,env = convert_to_c_binop op env in
                  let c_e2,env = convert_to_c_expression e2 env in
                  Sast.Binop(c_e1,c_op,c_e2),env
            )
      | Ast.Higher_Order_Function_Call(hof) -> 
       (* Check that function exists in environment *)
        if (is_function_in_scope (Utils.idtos(hof.kernel_function_name)) env) = false then raise (Exceptions.Function_not_defined (Utils.idtos hof.kernel_function_name));
        (* Check that arrays are valid arrays *)
(*         let input_arrays = List.map (fun e -> infer_type e env) hof.input_arrays in 
        let good_arrays = (List.iter same_types_list input_arrays) in *)
        (* Check that function arguments match that of function declaration *)
        let f_info = (get_function_info (Utils.idtos hof.kernel_function_name) env) in
        (* if f_info.function_type != Kernel_Device then raise (Exceptions.Higher_order_function_call_only_takes_defg_functions)
      else *)
        let expected_arg_types = f_info.function_args in 
        let get_array_types arr = 
            match arr with 
                | Ast.Array(t,n) -> t
                | _ -> raise Exceptions.Invalid_input_argument_to_map
        in
        let f_arg_types = List.map get_array_types (get_types hof.input_arrays [] env) in
        let check_args expected_arg_types f_args =
        List.map2 same_types expected_arg_types f_args in
        ignore(same_types (List.length f_arg_types) (List.length expected_arg_types));
        ignore(check_args f_arg_types expected_arg_types);
        (*Check that constants match those unknown variables in the defg*)
        let retrive_constant_name c = 
          match c with 
            | Ast.Constant(id,e) -> Utils.idtos(id)
        in
        let hof_call_constants_names = List.map (retrive_constant_name) hof.constants in
        let hof_constants_names = List.map (fun x -> Utils.idtos(x)) f_info.unknown_variables in 
          let rec check_constants hof_call_c hof_fdecl_c = 
            match hof_fdecl_c with
            | [] -> true
            | hd::tl -> if (List.exists (fun s -> s = hd) hof_call_c) = false then raise Exceptions.Constants_missing_in_defg
              else check_constants hof_call_c tl 
          in
        ignore(check_constants hof_call_constants_names hof_constants_names);
        (match Utils.idtos(hof.hof_type) with 
            | "map" ->
                (*Add the c map function to the environment*)
                let hof_c_fdecl = make_hof_c_fdecl hof env in
                let hof_ptx_fdecl = make_hof_ptx_fdecl hof_c_fdecl hof env in
                let env = update_hof_lists hof_c_fdecl hof_ptx_fdecl env in
                (* Convert *)
                Sast.Function_Call(hof_c_fdecl.higher_order_function_name,(List.map (fun x -> fst(convert_to_c_expression x env)) (List.rev hof.input_arrays))),env
            (* | "reduce" ->
                in Sast.FunctionCall(c_ma) *)
            | _ -> raise (Exceptions.Unknown_higher_order_function_call (Utils.idtos(hof.hof_type))))

(* TO IMPLEMENT *)
let convert_to_ptx_expression e env = 
  match e with 
    | Ast.Function_Call(id, exp) -> raise Exceptions.C'est_La_Vie
    | Ast.Higher_Order_Function_Call(hof) -> raise Exceptions.No_Hof_Allowed
    | Ast.String_Literal(s) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
    | Ast.Integer_Literal(i) -> Sast.Ptx_expression_variable(Sast.Constant_int(i)), env
    | Ast.Boolean_Literal(b) -> Sast.Ptx_expression_variable(Sast.Constant_bool(b)), env
    | Ast.Floating_Point_Literal(f) -> Sast.Ptx_expression_variable(Sast.Constant_float(f)), env
    | Ast.Array_Literal(e_list) -> raise Exceptions.C'est_La_Vie
    | Ast.Identifier_Literal(i) -> 
      let variable = get_variable_info (Utils.idtos i) env in
      let regStr = match variable.vtype with
        | Ast.Primitive(Ast.Integer) -> "%si" ^ (string_of_int(variable.register_number))
        | Ast.Primitive(Ast.Float) -> "%fl" ^ (string_of_int(variable.register_number))
        | Ast.Primitive(Ast.Boolean) -> "%pr" ^ (string_of_int(variable.register_number))
        | Ast.Primitive(Ast.String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
        | Ast.Primitive(Ast.Void) -> raise Exceptions.Void_type_in_gdecl
        | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_Vie
      in
      Sast.Ptx_expression_variable(Sast.Ptx_Variable(Ast.Identifier(regStr))), env
    | Ast.Cast(v_type, e) -> raise Exceptions.C'est_La_Vie
    | Ast.Binop(e1,o,e2) -> Sast.Ptx_empty, env
(*       if((same_types (infer_type e1 env) (infer_type e2 env)) = false) then raise (Exceptions.Type_mismatch "Binop doesn't match")
      else
      let val1 = match infer_type(e1,env) with
        | Ast.Primitive(Ast.Integer) -> let num = !signed_int_counter in (incr signed_int_counter ; num)
        | Ast.Primitive(Ast.Float) -> let num = !signed_float_counter in (incr signed_float_counter ; num)
        | Ast.Primitive(Ast.Boolean) -> let num = !predicate_counter in (incr predicate_counter ; num)
        | Ast.Primitive(Ast.String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
        | Ast.Primitive(Ast.Void) -> raise Exceptions.Void_type_in_gdecl
        | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_Vie
      in
      let val2 = match infer_type(e2,env) with
        | Ast.Primitive(Ast.Integer) -> let num = !signed_int_counter in (incr signed_int_counter ; num)
        | Ast.Primitive(Ast.Float) -> let num = !signed_float_counter in (incr signed_float_counter ; num)
        | Ast.Primitive(Ast.Boolean) -> let num = !predicate_counter in (incr predicate_counter ; num)
        | Ast.Primitive(Ast.String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
        | Ast.Primitive(Ast.Void) -> raise Exceptions.Void_type_in_gdecl
        | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_Vie
      in
      Ptx_Binop(
        convert_to_ptx_binop(o),
        convert_to_ptx_variable_type(infer_type(e1)),
        convert_to_ptx_expression()

      ) *)
(* Need a way to turn one Ast datatype into multiple Sast datatypes      
 convert_to_ptx_expression(e1) ^ 
      convert_to_ptx_expression(e2) ^ 
      convert_to_ptx_binop(o) *)
    | Ast.Unop(e, u) -> raise Exceptions.C'est_La_Vie
    | Ast.Array_Accessor(e, e_list,is_lvalue) -> raise Exceptions.C'est_La_Vie
    | Ast.Ternary(e1, e2, e3) -> raise Exceptions.C'est_La_Vie

let rec get_array_el_type arr num_dim =
  match num_dim with 
    | 1 -> 
      (match arr with 
        | Ast.Array(t,n) -> t
        | _ -> raise Exceptions.Not_an_array_expression
      )
    | _ ->
      if num_dim <= 0 then raise Exceptions.Invalid_accessor_value 
      else 
        (match arr with 
          | Ast.Array(t,n) -> get_array_el_type t (num_dim-1)
          | _ -> raise Exceptions.Not_an_array_expression
        )

let convert_to_c_variable_statement vstmt env = 
    match vstmt with 
      | Ast.Declaration(vdecl) -> (* Check that it isn't already declared in convert_to_c_vdecl *) 
            let c_vdecl, new_env = convert_to_c_vdecl vdecl env in
            Sast.Declaration(c_vdecl),new_env
      | Ast.Initialization(vdecl,e) ->
            (*Check same types*)
            let vtype = match vdecl with 
              | Ast.Variable_Declaration(v,id) -> v
            in
            ignore(same_types (vtype) (infer_type e env));
            (* Convert  - note vdecl also checks if declared *)
            let c_vdecl, env = convert_to_c_vdecl vdecl env in
            let c_e, env = convert_to_c_expression e env in
            Sast.Initialization(c_vdecl,c_e),env
      | Ast.Assignment(e1,e2) -> 
            (* Check that identifiers are declared *)
            match e1 with 
              | Ast.Identifier_Literal(id) -> 
                  if (check_already_declared (Utils.idtos(id)) env) = false then raise (Exceptions.Name_not_found (Utils.idtos id))
                  else
                    (* Check same types*)
                    ignore(same_types (get_variable_type (Utils.idtos id) env) (infer_type e2 env));
                    (*Convert*)
                    let c_e1, env = convert_to_c_expression e1 env in 
                    let c_e2, env = convert_to_c_expression e2 env in
                    Sast.Assignment(c_e1,c_e2),env
              | Ast.Array_Accessor(e,e_list,is_lvalue)->
                    (match e with 
                      | Ast.Identifier_Literal(id) -> 
                          if (check_already_declared (Utils.idtos id) env )= false then raise (Exceptions.Name_not_found (Utils.idtos id))
                          else
                            (* Check same types*)
                              let arr = get_variable_type (Utils.idtos id) env in ignore(same_types (get_array_el_type arr (List.length e_list)) (infer_type e2 env));
                              (*Convert*)
                              let c_e1, env = convert_to_c_expression e1 env in 
                              let c_e2,env = convert_to_c_expression e2 env in 
                              Sast.Assignment(c_e1,c_e2),env
                      | _ -> (raise Exceptions.Cannot_assign_expression)
                    )
              | _ -> raise Exceptions.Cannot_assign_expression

(* TO IMPLEMENT *)
let convert_to_ptx_variable_statement vstmt env =
    match vstmt with
      | Ast.Declaration(vdecl) -> 
          let new_env = convert_to_ptx_vdecl vdecl env in
          Ptx_empty, new_env
      | Ast.Initialization(vdecl, e) -> 
          let vtype = match vdecl with
            | Ast.Variable_Declaration(v, id) -> v
          in
          let regStr,env = (
            let regVal = match vtype with
              | Ast.Primitive(Ast.Integer) -> "%si" ^ (string_of_int(!signed_int_counter))
              | Ast.Primitive(Ast.Float) -> "%fl" ^ (string_of_int(!signed_float_counter))
              | Ast.Primitive(Ast.Boolean) -> "%pr" ^ (string_of_int(!predicate_counter))
              | Ast.Primitive(Ast.String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
              | Ast.Primitive(Ast.Void) -> raise Exceptions.Void_type_in_gdecl
              | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_Vie
            in
            let env2 = convert_to_ptx_vdecl vdecl env in
            regVal, env2) in
          let exp2, env = convert_to_ptx_expression e env in
          let v_type, env = convert_to_ptx_variable_type vtype env in
          let movInit = (
              Ptx_Move(
                v_type, Ptx_expression_variable(Ptx_Variable(Ast.Identifier(regStr))), exp2
              ),env) in
          let res = match e with 
            (*array accessor as well*)
            | Ast.Integer_Literal(i) -> movInit
            | Ast.Boolean_Literal(b) -> movInit
            | Ast.Floating_Point_Literal(f) -> movInit
            | Ast.Identifier_Literal(i) -> movInit
            | Ast.Binop(e1, o, e2) -> 
              let ptx_b, env = convert_to_ptx_binop o env in
              let bexp1, env = convert_to_ptx_expression e1 env in
              let bexp2, env = convert_to_ptx_expression e2 env in
              Sast.Ptx_Binop(
                ptx_b,
                v_type,
                Ptx_expression_variable(Ptx_Variable(Ast.Identifier(regStr))),
                bexp1,
                bexp2
            ), env
            | _ -> raise Exceptions.Not_an_array_expression
          in res
      | Ast.Assignment(e1, e2) -> raise Exceptions.C'est_La_Vie
(*       | Ast.Initialization(vdecl, expression) ->
        let 
          | Ast.Primitive(Integer) -> incr signed_int_counter ; !signed_int_counter
          | Ast.Primitive(Float) -> incr signed_float_counter ; !signed_float_counter
          | Ast.Primitive(Boolean) -> incr predicate_counter ; !predicate_counter
          | Ast.Primitive(String) -> raise Exceptions.NO_STRINGS_ALLOWED_IN_GDECL
          | Ast.Primitive(Void) -> raise Exceptions.Void_type_in_gdecl
          | Ast.Array(vtype2, i) -> raise Exceptions.C'est_La_vie

      | Assignment of expression * expression *)
            
        
(* Converts global vstmt list into c vstmt list *)
let rec convert_to_c_variable_statement_list vstmt_list c_vstmt_list env = 
     match vstmt_list with 
      | [] -> (c_vstmt_list,env)
      | hd::tl -> 
          let c_vstmt, env = convert_to_c_variable_statement hd env in
          convert_to_c_variable_statement_list tl (List.rev(c_vstmt::List.rev(c_vstmt_list))) env



(* Converts a list of something to another list *)
let rec convert_list func ast_list sast_list env = 
  match ast_list with 
    | [] -> sast_list,env
    | hd::tl -> 
      let sast_type,env = func hd env in 
      convert_list func tl (List.rev (sast_type::List.rev(sast_list))) env

let rec convert_to_c_statement stmt env = 
  match stmt with 
    | Ast.Variable_Statement(vstmt) -> 
        let c_vstmt,env = convert_to_c_variable_statement vstmt env in
        Sast.Variable_Statement(c_vstmt),env
    | Ast.Expression(e) -> 
        let c_e,env = convert_to_c_expression e env in 
        Sast.Expression(c_e),env
    | Ast.If(e,stmt1,stmt2) ->
        (* Check that e is a boolean expression *)
        ignore(same_types (infer_type e env) (Ast.Primitive(Ast.Boolean)));
        (* Convert*)
        let c_e, env = convert_to_c_expression e env in 
        let c_stmt1,env = convert_to_c_statement stmt1 env in 
        let c_stmt2,env = convert_to_c_statement stmt2 env in
        Sast.If(c_e,c_stmt1,c_stmt2),env
    | Ast.While(e,stmt) ->
        ignore(same_types (infer_type e env) (Ast.Primitive(Ast.Boolean)));
        (* Check that e is a boolean expression *)
        let c_e, env = convert_to_c_expression e env in 
        let c_stmt,env = convert_to_c_statement stmt env in
        Sast.While(c_e,c_stmt),env
    | Ast.For(stmt1,e,stmt2,stmt3) ->
        (* Check that stmt1 is an initialization expression *)
          (match stmt1 with
            | Ast.Variable_Statement(vstmt) ->
              (match vstmt with 
                | Ast.Assignment(e1,e2) -> ()
                | Ast.Initialization(vdecl,e) -> ()
                | _ -> raise Exceptions.Invalid_statement_in_for)
            | _ -> raise Exceptions.Invalid_statement_in_for);
        (* Check that e is a boolean expression *)
        ignore(same_types (infer_type e env) (Ast.Primitive(Ast.Boolean)));
        (* Convert *)
        let env = push_scope env in
        let c_stmt1,  env = convert_to_c_statement   stmt1 env   in
        let c_e,      env = convert_to_c_expression  e     env  in
        let c_stmt2,  env = convert_to_c_statement   stmt2 env  in
        let c_stmt3,  env = convert_to_c_statement   stmt3 env  in
        let env = pop_scope env in
        Sast.For(c_stmt1,c_e,c_stmt2,c_stmt3),env
    | Ast.Return(e) ->
        let c_e, env = convert_to_c_expression e env in
        Sast.Return(c_e),env
    | Ast.Return_Void -> Sast.Return_Void,env
    | Ast.Continue -> Sast.Continue,env
    | Ast.Break -> Sast.Break,env
    | Ast.Block(stmt_list) -> 
        (* Check that nothing follows a return , break, or continue in a block *)
        if (good_statement_order stmt_list) = false then raise Exceptions.Have_statements_after_return_break_continue
        else
        (* Convert *)
        let c_stmt_list,env = convert_list convert_to_c_statement stmt_list [] env in
         Sast.Block(c_stmt_list),env

let convert_to_ptx_statement stmt env =
  match stmt with 
    | Ast.Variable_Statement(v) -> 
      let ptx_vstmt,env = convert_to_ptx_variable_statement v env in
      Ptx_expression(ptx_vstmt),env
    | Ast.Expression(e) -> let e1, env = convert_to_ptx_expression e env in
      Ptx_expression(e1),env
    | Ast.Return_Void -> Ptx_expression(Sast.Ptx_Return_void), env
    | Ast.Block(stmt_list) -> raise Exceptions.C'est_La_Vie       
(*         if (good_statement_order stmt_list) = false then raise Exceptions.Have_statements_after_return_break_continue
        else
        let ptx_stmt_list,env = convert_list convert_to_ptx_statement stmt_list [] env in
          let subroutine = {
            routine_name : Ast.identifier;
            routine_expressions             : ptx_expression list;
          } *)

    | Ast.If(e, s1, s2) -> raise Exceptions.C'est_La_Vie
    | Ast.While(e, s) -> raise Exceptions.C'est_La_Vie
    | Ast.For(s1, e, s2, s3) -> raise Exceptions.C'est_La_Vie
    | Ast.Return(e) -> raise Exceptions.C'est_La_Vie
    | Ast.Continue -> raise Exceptions.C'est_La_Vie
    | Ast.Break -> raise Exceptions.C'est_La_Vie
    
let convert_to_c_param vdecl env  = 
    match vdecl with 
      | Ast.Variable_Declaration(vtype,id) ->
          if(check_already_declared (Utils.idtos id) env) = true then raise Exceptions.Variable_already_declared
          else
            let v_info = {
              vtype = vtype;
              register_number = 0;
            }
            in
            let updated_scope = Variable_Map.add (Utils.idtos id) v_info (List.hd env.variable_scope_stack) in
            let env = update_scope updated_scope env in
            let c_vtype, env = convert_to_c_variable_type vtype env in
            Sast.Variable_Declaration(c_vtype,id),env

let convert_to_ptx_param vdecl env =
  match vdecl with
    | Ast.Variable_Declaration(vtype,id) -> 
      match vtype with
      | Ast.Primitive(p) ->
        {
          ptx_parameter_data_type = fst(convert_to_ptx_data_type p env);
          ptx_parameter_state_space = Sast.State_undefined;
          ptx_parameter_name = id;
        },env
      | Ast.Array(t,n) -> raise (Exceptions.Exception("Array not a valid ptx param"))

(* Converts from fdecl to c_fdecl *)
let convert_to_c_fdecl fdecl env =
    if (is_function_in_scope (Utils.idtos fdecl.name) env) = true then (raise Exceptions.Function_already_declared)
    else
      let vdecl_to_param vdecl = 
        match vdecl with 
          | Ast.Variable_Declaration(vtype,id) -> vtype
      in
      (* Add to function map*)
      (let host_func_info = {
          function_type = Host;
          function_name = fdecl.name;
          function_return_type = fdecl.return_type;
          function_args = List.map vdecl_to_param fdecl.params;
          dependent_functions = [];
          unknown_variables = [];
      } 
      in
      let env = update_host_fmap host_func_info env in
      (* Push new scope for function *)
      let env = push_scope env in
      (* Do conversion while passing enviroment *)
      let return_type,  env    = convert_to_c_variable_type fdecl.return_type env in
      let params,       env    = convert_list convert_to_c_param         fdecl.params  [] env in
      let body,         env    = convert_list convert_to_c_statement     fdecl.body    [] env in
      let c_fdecl = {
        c_fdecl_return_type = return_type;
        c_fdecl_name = fdecl.name;
        c_fdecl_params = params;
        c_fdecl_body = body;
      }
      in
      (* Pop the variable scope for the function *)
      let env = pop_scope env in
      c_fdecl, env)

let convert_to_ptx_fdecl fdecl env =
    if (is_function_in_scope (Utils.idtos fdecl.name) env) = true then (raise Exceptions.Function_already_declared)
    else
      let vdecl_to_param vdecl = 
        match vdecl with 
          | Ast.Variable_Declaration(vtype,id) -> vtype
      in
      (* Add to function map*)
      (let host_func_info = {
          function_type = Kernel_Global;
          function_name = fdecl.name;
          function_return_type = fdecl.return_type;
          function_args = List.map vdecl_to_param fdecl.params;
          dependent_functions = [];
          unknown_variables = [];
      } 
      in
      let env = update_host_fmap host_func_info env in
      (* Push new scope for function *)
      let env = push_scope env in
      (* Do conversion while passing enviroment *)
      (*create a ptx_kernel_variable_info obj*)
      let return_type, env = convert_to_ptx_variable_type fdecl.return_type env in
      let return_info,  env    = {
        ptx_variable_type = return_type;
        ptx_kernel_name = fdecl.name;
      }, env in
      let params,env           = convert_list convert_to_ptx_param fdecl.params [] env in
      let body,         env    = convert_list convert_to_ptx_statement     fdecl.body    [] env in
      let registers,    env    =  [
        Ptx_Vdecl(Register_state, Sast.Ptx_Primitive(S32), Parameterized_variable_register(Ast.Identifier("si"), !signed_int_counter));
        Ptx_Vdecl(Register_state, Sast.Ptx_Primitive(F32), Parameterized_variable_register(Ast.Identifier("fl"), !signed_float_counter));
        Ptx_Vdecl(Register_state, Sast.Ptx_Primitive(Pred), Parameterized_variable_register(Ast.Identifier("pr"), !predicate_counter));
      ],  env in
      let ptx_fdecl = {
        ptx_fdecl_type = Sast.Device_func;
        ptx_fdecl_name = fdecl.name;
        ptx_fdecl_params = params;
        ptx_fdecl_return_type = fst(convert_to_ptx_param (Ast.Variable_Declaration (fdecl.return_type, (Ast.Identifier (generate_ptx_return_name()) ) )) env);
        register_decls = registers;
        ptx_fdecl_body = body;
      }
      in
      (* Pop the variable scope for the function *)
      let env = pop_scope env in
      ptx_fdecl, env) 

(* Converts a list of function declarations to ptx and c functions *)
let rec convert_fdecl_list fdecl_list ptx_fdecl_list c_fdecl_list env = 
     match fdecl_list with 
      | [] -> (ptx_fdecl_list,c_fdecl_list,env)
      | hd::tl -> 
       ( match hd.is_kernel_function with
          | false ->
              let c_fdecl, env = convert_to_c_fdecl hd env in 
              convert_fdecl_list tl ptx_fdecl_list (List.rev(c_fdecl::List.rev(c_fdecl_list))) env
          | true -> 
              let ptx_fdecl, env = convert_to_ptx_fdecl hd env in
              convert_fdecl_list tl (List.rev(ptx_fdecl::List.rev(ptx_fdecl_list))) c_fdecl_list env
        )

(* Main function for converting ast to sast *)
let convert ast env =
    let vstmt_list,env                      = convert_list convert_to_c_variable_statement (fst(ast)) [] env in
    let ptx_fdecl_list,c_fdecl_list, env    = convert_fdecl_list (snd(ast)) [] [] env in
    let sast                                = (vstmt_list,ptx_fdecl_list,(env.hof_ptx_function_list),(env.hof_c_function_list),c_fdecl_list) in 
    sast

(* Main function for Sast *)
let analyze ast =  
  let env = init_env in
  let sast = convert ast env in
  sast

