port module DurableClassifierWorker exposing (main)

import Json.Encode as Encode
import Platform
import Schelm.Node.FileSystem.AtomicText as AtomicText
import Task


port report : Encode.Value -> Cmd msg


type Msg
    = GotError (Result AtomicText.ReplaceFailure AtomicText.ReplaceResult)


type alias Flags =
    { root : String, segments : List String, invalidText : String }


main : Program Flags () Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = always Sub.none
        }


init : Flags -> ( (), Cmd Msg )
init flags =
    case ( AtomicText.root flags.root, AtomicText.fileAt flags.segments ) of
        ( Ok appRoot, Ok target ) ->
            ( (), AtomicText.replace appRoot target flags.invalidText |> Task.attempt GotError )

        _ ->
            ( (), report (Encode.object [ ( "kind", Encode.string "invalid-flags" ) ]) )


update : Msg -> () -> ( (), Cmd Msg )
update (GotError result) model =
    case result of
        Err failure ->
            let
                operationError =
                    AtomicText.failureError failure
            in
            ( model
            , report
                (Encode.list identity
                    [ classify "durable-clean"
                        (AtomicText.RenameAcknowledged
                            { durability = AtomicText.FileAndDirectorySyncAcknowledged
                            , cleanup = AtomicText.CleanupAcknowledged
                            }
                        )
                    , classify "durable-residue"
                        (AtomicText.RenameAcknowledged
                            { durability = AtomicText.FileAndDirectorySyncAcknowledged
                            , cleanup = AtomicText.CleanupIncomplete [ AtomicText.ParentDescriptorMayRemain ]
                            }
                        )
                    , classify "unconfirmed-clean"
                        (AtomicText.RenameAcknowledged
                            { durability = AtomicText.DurabilityUnconfirmed AtomicText.SyncingParent operationError
                            , cleanup = AtomicText.CleanupAcknowledged
                            }
                        )
                    , classify "unconfirmed-residue"
                        (AtomicText.RenameAcknowledged
                            { durability = AtomicText.DurabilityUnconfirmed AtomicText.OpeningParent operationError
                            , cleanup = AtomicText.CleanupIncomplete [ AtomicText.TempMayRemain, AtomicText.ParentDescriptorMayRemain ]
                            }
                        )
                    ]
                )
            )

        Ok _ ->
            ( model, report (Encode.object [ ( "kind", Encode.string "expected-invalid-text" ) ]) )


classify : String -> AtomicText.ReplaceResult -> Encode.Value
classify label outcome =
    Encode.object
        [ ( "label", Encode.string label )
        , ( "classification"
          , case AtomicText.requireDurable outcome of
                Ok () ->
                    Encode.object [ ( "kind", Encode.string "ok" ) ]

                Err (AtomicText.ReplacementNotAcknowledged _) ->
                    Encode.object [ ( "kind", Encode.string "not-acknowledged" ) ]

                Err (AtomicText.ReplacementInstalledButDurabilityUnconfirmed stage operationError cleanup) ->
                    Encode.object
                        [ ( "kind", Encode.string "unconfirmed" )
                        , ( "stage", Encode.string (stageName stage) )
                        , ( "errorKind", Encode.string (errorKindName (AtomicText.errorKind operationError)) )
                        , ( "errorCode", Maybe.withDefault Encode.null (Maybe.map Encode.string (AtomicText.errorCode operationError)) )
                        , ( "errorMessage", Encode.string (AtomicText.errorMessage operationError) )
                        , ( "residue", Encode.list (residueName >> Encode.string) (AtomicText.cleanupResidue cleanup) )
                        ]

                Err (AtomicText.ReplacementDurableButCleanupIncomplete residue) ->
                    Encode.object
                        [ ( "kind", Encode.string "durable-residue" )
                        , ( "residue", Encode.list (residueName >> Encode.string) residue )
                        ]
          )
        ]


stageName : AtomicText.DurabilityStage -> String
stageName stage =
    case stage of
        AtomicText.OpeningParent ->
            "opening-parent"

        AtomicText.SyncingParent ->
            "syncing-parent"

        AtomicText.ClosingParent ->
            "closing-parent"


errorKindName : AtomicText.ErrorKind -> String
errorKindName kind =
    case kind of
        AtomicText.InvalidInput ->
            "invalid-input"

        _ ->
            "unexpected"


residueName : AtomicText.Residue -> String
residueName residue =
    case residue of
        AtomicText.TempMayRemain ->
            "temp-may-remain"

        AtomicText.TempDescriptorMayRemain ->
            "temp-descriptor-may-remain"

        AtomicText.ParentDescriptorMayRemain ->
            "parent-descriptor-may-remain"
