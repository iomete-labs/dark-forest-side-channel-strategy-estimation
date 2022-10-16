
type share_action =
  | Share_fake_planet
  | Share_legit_planet
  | Dont_share

(** branch on the sender X rounds ago *)
type branch =
  | If_shared_legit
  | If_shared_fake
  | If_didnt_share

type conditional = branch * int
(** branch on whether this action took place X rounds ago *)

type respond_action =
  | Research_planet
  | Dont_research_planet

let _string_of_share_action = function
  | Share_fake_planet -> "share fake planet"
  | Share_legit_planet -> "share legit planet"
  | Dont_share -> "don't share"

let _string_of_respond_action = function
  | Research_planet -> "research planet"
  | Dont_research_planet -> "don't research planet"

let solve_payoff sender responder = match sender, responder with
  | Share_fake_planet, Research_planet -> 1, -1
  | Share_legit_planet, Dont_research_planet -> 1, 0
  | Share_fake_planet, Dont_research_planet -> -1, 0
  | Share_legit_planet, Research_planet -> 2, 1
  | Dont_share, Research_planet -> 0, 0
  | Dont_share, Dont_research_planet -> 0, 0

(** return whether the true or false branch should be used in a responding
  * conditional *)
let solve_branch branch sender_program =
  match branch, sender_program with
  | If_shared_legit, Share_legit_planet -> true
  | If_shared_legit, Share_fake_planet -> false
  | If_shared_legit, Dont_share -> false
  | If_shared_fake, Share_fake_planet -> true
  | If_shared_fake, Share_legit_planet -> false
  | If_shared_fake, Dont_share -> false
  | If_didnt_share, Dont_share -> true
  | If_didnt_share, Share_legit_planet -> false
  | If_didnt_share, Share_fake_planet -> false

type 'a program_conditional =
  { conditional : conditional option
  ; on_true     : 'a
  ; on_false    : 'a }

let print_respond_action fmt =
  let p = Format.fprintf fmt in
  function
  | Research_planet -> p "researchplanet"
  | Dont_research_planet -> p "dontresearchplanet"

let print_branch fmt =
  let p = Format.fprintf fmt in
  function
  | If_shared_legit, rounds_ago -> p "ifsharedlegit(%d)" rounds_ago
  | If_shared_fake, rounds_ago -> p "ifsharedfake(%d)" rounds_ago
  | If_didnt_share, rounds_ago -> p "ifdidntshare(%d)" rounds_ago

let print_program_conditional fmt { conditional ; on_true ; on_false } =
  let p = Format.fprintf fmt in
  match conditional with
  | Some conditional ->
    print_branch fmt conditional;
    p ":";
    print_respond_action fmt on_true;
    p ":";
    print_respond_action fmt on_false
  | None ->
    print_respond_action fmt on_true

type program = share_action array * respond_action program_conditional array

let print_program fmt (share_actions, respond_actions) =
  let p = Format.fprintf fmt in

  share_actions |> Array.iter begin function
    | Share_fake_planet -> p "sharefakeplanet;"
    | Share_legit_planet -> p "sharelegitplanet;"
    | Dont_share -> p "dontshare;"
  end;

  p ",";

  respond_actions |> Array.iter begin fun action ->
    print_program_conditional fmt action;
    p ";"
  end

let share_action_create () =
  match Random.int 3 with
  | 0 -> Share_fake_planet
  | 1 -> Share_legit_planet
  | 2 -> Dont_share
  | _ -> assert false

let respond_action_create () =
  match Random.int 2 with
  | 0 -> Research_planet
  | 1 -> Dont_research_planet
  | _ -> assert false

let round_select = Random.int

let conditional_create ~rounds () =
  match Random.int 4 with
  | 0 -> Some (If_shared_legit, round_select rounds)
  | 1 -> Some (If_shared_fake, round_select rounds)
  | 2 -> Some (If_didnt_share, round_select rounds)
  | 3 -> None
  | _ -> assert false

let program_conditional_create ~rounds branch_f =
  { conditional = conditional_create ~rounds ()
  ; on_true = branch_f ()
  ; on_false = branch_f () }

let program_sender_conditional_create ?(rounds = 10) () =
  Array.init
    rounds
    (fun _ -> share_action_create () )

let program_responder_conditional_create ?(rounds = 10) () =
  Array.init
    rounds
    (fun _ -> program_conditional_create ~rounds respond_action_create )

let program_conditional_create ?(rounds = 10) () =
  program_sender_conditional_create ~rounds (),
  program_responder_conditional_create ~rounds ()

type environment = program array

let environment_create ?(players = 10) ?(rounds = 10) : unit -> environment =
  fun () ->
  Array.init players (fun _ -> program_conditional_create ~rounds ())

type scores = int array

let array_wraparound_get arr current_pos selected_pos =
  let length = Array.length arr - 1 in
  let new_pos = current_pos + selected_pos in
  Array.get arr (
    if new_pos > length then new_pos - length else new_pos
  )

let solve_responder_conditional sender_programs current_round = function
  | { conditional = Some (branch, round); on_true ; on_false } ->
    let sender_program = array_wraparound_get sender_programs current_round round in
    if solve_branch branch sender_program then on_true else on_false
  | { conditional = None ; on_true ; _ } -> on_true

let play_game ?(players = 100) ?(rounds = 10) () =
  let environment = environment_create ~players ~rounds () in
  let scores : scores = Array.init players (fun _ -> 0) in

  let iteri_environment f = Array.iteri f environment in

  for round = 0 to rounds - 1 do
    iteri_environment begin fun sender_i (sender_programs, _) ->
        iteri_environment begin fun responder_i (_, responder_programs) ->
          let sender_program = Array.get sender_programs round  in

          let responder_program_conditional = Array.get responder_programs round in

          let responder_program =
            solve_responder_conditional
            sender_programs
            round
            responder_program_conditional in

          let add_sender_score, add_responder_score =
            solve_payoff sender_program responder_program in

          let sender_score = Array.get scores sender_i in

          let responder_score = Array.get scores responder_i in

          Array.set scores sender_i (sender_score + add_sender_score);

          Array.set scores responder_i (responder_score + add_responder_score)
        end
    end
  done;

  environment, scores

let () =
  Random.self_init ();
  let environment, scores = play_game ~players:10000 ~rounds:3 () in

  environment |> Array.iteri begin fun player program ->
    let score = Array.get scores player in
    print_program Format.std_formatter program;
    Printf.printf ",%d\n" score
  end