module WriterModelTest exposing (tests)

import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)


type Owner
    = Absent
    | Writing Int
    | Ready
    | Closing


type Command
    = Start Int
    | Reply Int
    | BeginClose


step : Command -> Owner -> ( Owner, Int )
step command owner =
    case ( command, owner ) of
        ( Start request, Absent ) ->
            ( Writing request, 1 )

        ( Reply request, Writing current ) ->
            if request == current then
                ( Ready, 0 )

            else
                ( owner, 1 )

        ( BeginClose, _ ) ->
            ( Closing, 0 )

        _ ->
            ( owner
            , if isWriting owner then
                1

              else
                0
            )


isWriting : Owner -> Bool
isWriting owner =
    case owner of
        Writing _ ->
            True

        _ ->
            False


tests : Test
tests =
    describe "daemon rendezvous owner model"
        [ fuzz (Fuzz.list (Fuzz.intRange 0 20)) "late replies never create a second write" <|
            \replies ->
                let
                    final =
                        List.foldl (\request ( owner, _ ) -> step (Reply request) owner) (step (Start 7) Absent) replies
                in
                Tuple.second final
                    |> Expect.atMost 1
        , test "closing suppresses future starts" <|
            \_ ->
                step (Start 2) (Tuple.first (step BeginClose (Writing 1)))
                    |> Expect.equal ( Closing, 0 )
        ]
