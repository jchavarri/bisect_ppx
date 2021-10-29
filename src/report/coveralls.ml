(* This file is part of Bisect_ppx, released under the MIT license. See
   LICENSE.md for details, or visit
   https://github.com/aantron/bisect_ppx/blob/master/LICENSE.md. *)



let file_json indent in_file resolver visited points =
  Util.info "Processing file '%s'..." in_file;
  match resolver in_file with
  | None ->
    Util.info "... file not found";
    None
  | Some resolved_in_file ->
    let digest = Digest.to_hex (Digest.file resolved_in_file) in
    let line_counts =
      Util.line_counts in_file resolved_in_file visited points in
    let scounts =
      line_counts
      |> List.map (function
        | None -> "null"
        | Some nb -> Printf.sprintf "%d" nb)
    in
    let coverage = String.concat "," scounts in
    let indent_strings indent l =
      let i = String.make indent ' ' in
      List.map (fun s -> i ^ s) l
    in
    Some begin
      [
        "{";
        Printf.sprintf "    \"name\": \"%s\"," in_file;
        Printf.sprintf "    \"source_digest\": \"%s\"," digest;
        Printf.sprintf "    \"coverage\": [%s]" coverage;
        "}";
      ]
      |> indent_strings indent
      |> String.concat "\n"
    end

let output_of command =
  let channel = Unix.open_process_in command in
  let line = input_line channel in
  match Unix.close_process_in channel with
  | WEXITED 0 ->
    line
  | _ ->
    Printf.eprintf "Error: command failed: '%s'\n%!" command;
    exit 1

let metadata name field =
  output_of ("git log -1 --pretty=format:'" ^ field ^ "'")
  |> String.escaped
  |> Printf.sprintf "\"%s\":\"%s\"" name

let output
    file
    service_name
    service_number
    service_job_id
    service_pull_request
    repo_token
    git
    parallel
    resolver
    data
    points =

  let git =
    if not git then
      ""
    else
      let metadata =
        String.concat "," [
          metadata "id" "%H";
          metadata "author_name" "%an";
          metadata "author_email" "%ae";
          metadata "committer_name" "%cn";
          metadata "committer_email" "%ce";
          metadata "message" "%s";
        ]
      in
      let branch = output_of "git rev-parse --abbrev-ref HEAD" in
      Printf.sprintf
        "    \"git\":{\"head\":{%s},\"branch\":\"%s\",\"remotes\":{}},"
        metadata branch
  in

  Util.mkdirs (Filename.dirname file);
  let file_jsons =
    Hashtbl.fold begin fun in_file visited acc ->
      let maybe_json = file_json 8 in_file resolver visited points in
      match maybe_json with
      | None -> acc
      | Some s -> s::acc
    end data []
  in
  let repo_params =
    [
      "service_name", (String.trim service_name);
      "service_number", (String.trim service_number);
      "service_job_id", (String.trim service_job_id);
      "service_pull_request", (String.trim service_pull_request);
      "repo_token", (String.trim repo_token);
    ]
    |> List.filter (fun (_, v) -> (String.length v) > 0)
    |> List.map (fun (n, v) -> Printf.sprintf "    \"%s\": \"%s\"," n v)
    |> String.concat "\n"
  in
  let parallel =
    if parallel then
      "    \"parallel\": true,"
    else
      ""
  in
  let write ch =
    Util.output_strings
      [
        "{";
        repo_params;
        git;
        parallel;
        "    \"source_files\": [";
        (String.concat ",\n" file_jsons);
        "    ]";
        "}";
      ]
      []
      ch
  in
  match file with
  | "-" -> write stdout
  | f -> Bisect_common.try_out_channel false f write