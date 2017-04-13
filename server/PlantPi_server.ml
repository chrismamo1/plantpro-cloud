module StdList = struct
  include List
end

open Opium.Std
open Lwt.Infix
open CalendarLib

module List = struct
  include StdList
end

let _ =
  let open Email in
  ()

(*let service_get_oauth = get "/" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  `String ("received request \"" ^ body ^ "\"")
  |> respond')*)

let service_create_account = post "/create-account" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  let params = Fuck_stdlib.get_post_params body in
  let _, username =
    List.find
      (fun (name, _) -> name = "username")
      params
  in
  let _, password1 =
    List.find
      (fun (name, _) -> name = "password1")
      params
  in
  let _, password2 =
    List.find
      (fun (name, _) -> name = "password2")
      params
  in
  if password1 <> password2
  then respond' (`String ("passwords do not match: " ^ username))
  else begin
    match%lwt Db.get_user username with
      | Some _ ->
          respond'
            ~headers:(Cohttp.Header.init_with "Location" "/static/index.html#failed")
            ~code:(`Moved_permanently)
            (`String ("Error: User " ^ username ^ " already exists"))
      | None ->
          let user =
            User.create username "none@example.com" password1
          in
          let%lwt res = Db.add_user user in
          respond'
            (`String
              (Printf.sprintf
                "created user with ID %d"
                (Int64.to_int res)))
  end)

let service_create_group = post "/create-group" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  let params = Fuck_stdlib.get_post_params body in
  let _, username =
    List.find
      (fun (name, _) -> name = "user")
      params
  in
  let _, group_name =
    List.find
      (fun (name, _) -> name = "groupName")
      params
  in
  let%lwt user = Db.get_user username in
  let%lwt res = Db.add_group group_name username in
  respond'
    (`String
      (Printf.sprintf
        "created group with ID %d"
        (Int64.to_int res))))

let service_login = post "/login" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  let params = Fuck_stdlib.get_post_params body in
  let _, username =
    List.find
      (fun (name, _) -> name = "username")
      params
  in
  let _, password =
    List.find
      (fun (name, _) -> name = "password")
      params
  in
  let%lwt user = Db.get_user username in
  match user with
    | Some u ->
        begin match User.check username password u with
          | `Ok ->
              let session =
                Session.create username
              in
              let lifetime = Int64.of_int Session.lifetime in
              let cookie =
                Cohttp.Cookie.Set_cookie_hdr.make
                  ~expiration:(`Max_age (lifetime))
                  ~path:"/"
                  ~secure:false
                  ("auth_token", Encrypt.hex_encode session.auth_token)
              in
              let cookie' =
                Cohttp.Cookie.Set_cookie_hdr.make
                  ~expiration:(`Max_age (lifetime))
                  ~path:"/"
                  ~secure:false
                  ("username", Encrypt.hex_encode session.user)
              in
              let headers =
                let k, v = Cohttp.Cookie.Set_cookie_hdr.serialize cookie in
                let k', v' = Cohttp.Cookie.Set_cookie_hdr.serialize cookie' in
                Cohttp.Header.(add (init_with k v) k' v')
              in
              redirect'
                ~headers
                (Uri.of_string "/static/controlpanel/dashboard.html")
          | `Nope ->
              redirect'
                (Uri.of_string "/static/index.html#bad-pass")
        end
    | None ->
        redirect'
          (Uri.of_string "/static/index.html#not-found"))

let service_get_user_devices = get "/get-devices/:username/:group" (fun req ->
  let username = param req "username" in
  let%lwt devices = Db.get_devices username in
  let%lwt devices =
    match param req "group" |> Netencoding.Url.decode with
      | "all" ->
          Lwt.return devices
      | "ungrouped" ->
          List.filter (fun dev -> dev.Device.group = None) devices
          |> Lwt.return
      | target_group_name ->
          let%lwt user = Db.get_user username in
          begin match user with
            | Some user ->
                let%lwt group = Db.get_group_by_name target_group_name user in
                Lwt.return (
                  List.filter
                    (function
                      | { Device.group = Some { name = group_name } } when group_name = target_group_name ->
                          true
                      | _ ->
                          false)
                    devices)
            | None ->
                raise Not_found
          end
  in
  `Json ([%to_yojson: Device.t list] devices)
  |> respond')

let service_get_user_groups = get "/get-groups/:username" (fun req ->
  let username = param req "username" in
  let%lwt groups = Db.get_groups username in
  let groups =
    [%to_yojson: Group.t list] groups
  in
  `Json groups
  |> respond')

let try_unoption = function
  | Some x -> x
  | None -> raise (Failure "gambled and lost, mate *shrugs*")

let service_get_device_data = get "/get-data/:device" (fun req ->
  let device_name = param req "device" in
  let%lwt device =
    Db.get_device_by_name device_name
  in
  let device = try_unoption device in
  let%lwt data = Db.get_data device in
  let res =
    [%to_yojson: Device.sensor_reading list] data
  in
  (*`String device.name*)
  `Json res
  |> respond')

let service_associate_device = post "/associate-device" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  let params = Fuck_stdlib.get_post_params body in
  let username = "penis" in
  let username =
    match Cohttp.Header.get (Request.headers req) "Cookie" with
      | Some s ->
          Fuck_stdlib.get_post_params ~split_on:";" s
          (*|> List.fold_left (fun acc (name, x) -> acc ^ "<br />" ^ name ^ " " ^ x) ""*)
          |> List.find (fun (name, _) -> String.trim name = "username")
          |> snd
          |> Encrypt.hex_decode
      | None -> "no cookies"
  in
  let _, device =
    List.find
      (fun (name, _) -> name = "device")
      params
  in
  let _, name =
    List.find
      (fun (name, _) -> name = "name")
      params
  in
  let%lwt res = Db.associate_device username device name in
  match Int64.to_int res with
    | 1 ->
        respond' (`String "Successfully associated user")
    | _ ->
        respond' (`String "Error: device association unsuccessful"))

let service_push_data = post "/push-data" (fun req ->
  Cohttp_lwt_body.to_string
    req.Opium_rock.Request.body
  >>= fun body ->
  let packet =
    Yojson.Safe.from_string body
    |> Device.data_packet_of_yojson
  in
  let open Result in
  match packet with
    | Ok packet ->
        let open Device in
        let sclass = sclass_of_data_packet_payload packet.payload in
        let `Jeffrey(value, _) = packet.payload in
        let%lwt _ =
          Db.add_data
            (Calendar.now ())
            (B64.decode packet.Device.device)
            sclass
            (string_of_float value)
        in
        `String "OK"
        |> respond'
    | Error msg ->
        raise (Failure ("MALFORMED JSON: " ^ msg));)

(*let auth_static =
  let filter handler req =
    let headers = Request.headers req in
    let auth_token =
      Cohttp.Cookie.Set_cookie_hdr.(
        extract headers
        |> List.find (fun (name, _) -> name = "auth_token")
        |> snd
        |> value)
    in
    let username =
      Cohttp.Cookie.Set_cookie_hdr.(
        extract headers
        |> List.find (fun (name, _) -> name = "name")
        |> snd
        |> value)
    in
    let is_secure =
      try
        Cohttp.Request.uri req.request
        |> Uri.path
        |> String.substr_index ~pattern:"/secure/"
        |> Option.is_some
      with
        | Not_found -> false
    in
    match Session.check username auth_token, is_secure with
      | `Expired, true ->
        redirect'
          (Uri.of_string "/static/login.html#session-expired")
      | `Nope, true ->
        redirect'
          (Uri.of_string "/static/login.html#bad-auth")
      | `Ok, true
      | `Nope, false
      | `Expired, false ->
          Printf.printf "Handling with normal handler\n";
          handler req
  in
  Rock.Middleware.create ~filter*)

let _ =
  let plantpi_handle_signal = function
    | 2 | 3 | 9 | 15 | -6 ->
        ignore(
          print_endline "Handling signal.";
          Lwt_main.run (Db.close_db());
          exit 0)
    | n ->
        Printf.printf "Handling another signal: %d\n" n;
        print_endline "Some other signal.";
  in
  Sys.(
    set_signal 2 (Signal_handle plantpi_handle_signal);
    set_signal 3 (Signal_handle plantpi_handle_signal);
    set_signal 15 (Signal_handle plantpi_handle_signal););
  let static =
    Middleware.static ~local_path:"../client" ~uri_prefix:"/static"
  in
  App.empty
  |> service_create_account
  |> service_create_group
  |> service_login
  |> service_push_data
  |> service_associate_device
  |> service_get_user_devices
  |> service_get_user_groups
  |> service_get_device_data
  |> middleware static
  |> App.run_command
