type operator =
| Add | Subtract | Multiply | Divide | Modulo

type identifier = 
    Identifier of string

type variable_type = 
	| String
	| Integer
	| Array of variable_type * int
(* 	| Struct of variable_type list * expression list * int *)

type vdecl = {
    v_type   : variable_type;   
    name     : identifier;
}

type expression =
    | Binop of expression * operator * expression
	| String_Literal of string
	| Integer_Literal of int
    | Array_Literal of expression list 
	| Function_Call of identifier * expression list
	| Identifier_Expression of identifier
    | Map_Call of map_call
    | Reduce_Call of reduce_call
and constant = 
    | Constant of identifier * expression
and map_call = {
    map_function            : identifier;
    map_constants           : constant list;
    map_arrays              : expression list; (* Check in semantic analyzer that type is array*)
}
and reduce_call = {
    reduce_function         : identifier;
    reduce_constants        : constant list;
    reduce_arrays           : expression list; (* Check in semantic analyzer that type is array*)
}

type statement = 
    | Declaration of vdecl
    | Expression of expression
    | Assignment of identifier * expression
    | Return of expression
    | Initialization of vdecl * expression
	
type fdecl = {
    r_type      : variable_type;
    name        : identifier;
    params      : vdecl list;    
    body        : statement list;
}

(* Kernel AST types *)

type kernel_fdecl = {
    kernel_r_type      : variable_type;
    kernel_name        : identifier;
    kernel_params      : vdecl list;
    kernel_body        : statement list;
}
(* Program Definition *)
type program = vdecl list * kernel_fdecl list * fdecl list