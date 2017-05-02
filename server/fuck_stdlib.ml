open ExtString

let get_post_params ?(split_on="&") body =
  let lines = String.nsplit body split_on in
  List.map
    (fun line ->
      let a, b = String.split line "=" in
      Netencoding.Url.(decode a, decode b))
    lines

module List = struct
  include List

  let rec after ls x =
    match ls with
      | hd :: tl when hd = x ->
          tl
      | hd :: tl when hd <> x ->
          after tl x
      | [] ->
          raise Not_found

  let before ls x =
    let rec aux acc x = function
        | hd :: tl when hd = x ->
            acc
        | hd :: tl when hd <> x ->
            aux (acc @ [hd]) x tl
        | [] ->
            raise Not_found
    in
    aux [] x ls
end

let lwt_memoize f max =
  let memos = Hashtbl.create 32 in
  let eles = ref [] in
  fun x ->
    try
      let y = Hashtbl.find memos x in
      let after = List.after !eles x in
      let before = List.before !eles x in
      eles := before @ ((List.hd after) :: x :: (List.tl after));
      Lwt.return y
    with
      | Not_found ->
          let%lwt y = f x in
          Hashtbl.add memos x y;
          if Hashtbl.length memos > max
          then begin
            eles := List.tl !eles;
          end;
          eles := x :: !eles;
          Lwt.return y
