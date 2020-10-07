module Pages.Groups exposing (Model, Msg, Params, page)

import Api.Auth exposing (Auth)
import Api.Data as Data exposing (Data)
import Api.Group as Group exposing (Group)
import Api.Node as Node exposing (Node)
import Api.Response exposing (Response)
import Api.User as User exposing (User)
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Http
import List.Extra
import Shared
import Spa.Document exposing (Document)
import Spa.Generated.Route as Route
import Spa.Page as Page exposing (Page)
import Spa.Url exposing (Url)
import UI.Form as Form
import UI.Icon as Icon
import UI.Style as Style
import Utils.Route


page : Page Params Model Msg
page =
    Page.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , save = save
        , load = load
        }



-- INIT


type alias Params =
    ()


type alias Model =
    { auth : Auth
    , groupEdit : Maybe Group
    , newUser : Maybe NewUser
    , newNode : Maybe NewNode
    , error : Maybe String
    , groups : List Group
    , nodes : List Node
    , users : List User
    , newGroupUserFound : Maybe User
    , newGroupNodeFound : Maybe Node
    }


defaultModel : Model
defaultModel =
    { auth = { email = "", token = "", isRoot = False }
    , groupEdit = Nothing
    , newUser = Nothing
    , newNode = Nothing
    , error = Nothing
    , groups = []
    , nodes = []
    , users = []
    , newGroupUserFound = Nothing
    , newGroupNodeFound = Nothing
    }


type alias NewUser =
    { groupId : String
    , userEmail : String
    }


type alias NewNode =
    { groupId : String
    , nodeId : String
    }


init : Shared.Model -> Url Params -> ( Model, Cmd Msg )
init shared _ =
    case shared.auth of
        Just auth ->
            let
                model =
                    { defaultModel | auth = auth }
            in
            ( model
            , Cmd.batch
                [ User.list { token = auth.token, onResponse = ApiRespUserList }
                , Node.list { token = auth.token, onResponse = ApiRespNodeList }
                , Group.list { token = auth.token, onResponse = ApiRespList }
                ]
            )

        Nothing ->
            ( defaultModel
            , Utils.Route.navigate shared.key Route.SignIn
            )



-- UPDATE


type Msg
    = EditGroup Group
    | DiscardGroupEdits
    | New
    | AddUser String
    | CancelAddUser
    | EditNewUser String
    | AddNode String
    | CancelAddNode
    | EditNewNode String
    | ApiUpdate Group
    | ApiDelete String
    | ApiNewNode String String
    | ApiRemoveNode String String
    | ApiNewUser Group String
    | ApiRemoveUser Group String
    | ApiRespUpdate (Data Response)
    | ApiRespDelete (Data Response)
    | ApiRespNewNode (Data Response)
    | ApiRespUserList (Data (List User))
    | ApiRespNodeList (Data (List Node))
    | ApiRespList (Data (List Group))
    | ApiRespGetUserByEmail (Data User)
    | ApiRespGetNodeById (Data Node)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EditGroup group ->
            ( { model | groupEdit = Just group }
            , Cmd.none
            )

        DiscardGroupEdits ->
            ( { model | groupEdit = Nothing }
            , Cmd.none
            )

        New ->
            ( { model | groupEdit = Just Group.empty }
            , Cmd.none
            )

        AddUser groupId ->
            ( { model
                | newUser = Just { groupId = groupId, userEmail = "" }
                , newGroupUserFound = Nothing
              }
            , Cmd.none
            )

        CancelAddUser ->
            ( { model | newUser = Nothing }
            , Cmd.none
            )

        EditNewUser userEmail ->
            case model.newUser of
                Just newUser ->
                    ( { model | newUser = Just { newUser | userEmail = userEmail } }
                    , User.getByEmail
                        { token = model.auth.token
                        , email = userEmail
                        , onResponse = ApiRespGetUserByEmail
                        }
                    )

                Nothing ->
                    ( model, Cmd.none )

        AddNode groupId ->
            ( { model
                | newNode = Just { groupId = groupId, nodeId = "" }
                , newGroupNodeFound = Nothing
              }
            , Cmd.none
            )

        CancelAddNode ->
            ( { model | newNode = Nothing }
            , Cmd.none
            )

        EditNewNode nodeId ->
            case model.newNode of
                Just newNode ->
                    ( { model | newNode = Just { newNode | nodeId = nodeId } }
                    , Node.get
                        { token = model.auth.token
                        , id = nodeId
                        , onResponse = ApiRespGetNodeById
                        }
                    )

                Nothing ->
                    ( model, Cmd.none )

        ApiUpdate group ->
            let
                -- optimistically update groups
                groups =
                    List.map
                        (\g ->
                            if g.id == group.id then
                                group

                            else
                                g
                        )
                        model.groups
            in
            ( { model | groupEdit = Nothing, groups = groups }
            , Group.update
                { token = model.auth.token
                , group = group
                , onResponse = ApiRespUpdate
                }
            )

        ApiDelete id ->
            let
                -- optimistically delete group
                groups =
                    List.filter (\g -> g.id /= id) model.groups
            in
            ( { model | groupEdit = Nothing, groups = groups }
            , Group.delete
                { token = model.auth.token
                , id = id
                , onResponse = ApiRespDelete
                }
            )

        ApiRemoveUser group userId ->
            let
                users =
                    List.filter
                        (\ur -> ur.userId /= userId)
                        group.users

                updatedGroup =
                    { group | users = users }

                -- optimistically update groups
                groups =
                    List.map
                        (\g ->
                            if g.id == group.id then
                                group

                            else
                                g
                        )
                        model.groups
            in
            ( { model | groups = groups }
            , Group.update
                { token = model.auth.token
                , group = updatedGroup
                , onResponse = ApiRespUpdate
                }
            )

        ApiNewUser group userId ->
            let
                -- only add user if it does not already exist
                users =
                    case
                        List.Extra.find
                            (\ur -> ur.userId == userId)
                            group.users
                    of
                        Just _ ->
                            group.users

                        Nothing ->
                            { userId = userId, roles = [ "user" ] } :: group.users

                updatedGroup =
                    { group | users = users }

                -- optimistically update groups
                groups =
                    List.map
                        (\g ->
                            if g.id == group.id then
                                group

                            else
                                g
                        )
                        model.groups
            in
            ( { model | newUser = Nothing, groups = groups }
            , Group.update
                { token = model.auth.token
                , group = updatedGroup
                , onResponse = ApiRespUpdate
                }
            )

        ApiRemoveNode nodeId groupId ->
            case
                List.Extra.find (\d -> d.id == nodeId) model.nodes
            of
                Just node ->
                    let
                        groups =
                            List.filter (\o -> o /= groupId)
                                node.groups

                        -- optimistically update nodes
                        updatedNode =
                            { node | groups = groups }

                        nodes =
                            List.map
                                (\d ->
                                    if d.id == node.id then
                                        updatedNode

                                    else
                                        d
                                )
                                model.nodes
                    in
                    ( { model | nodes = nodes }
                    , Node.postGroups
                        { token = model.auth.token
                        , id = node.id
                        , groups = groups
                        , onResponse = ApiRespNewNode
                        }
                    )

                Nothing ->
                    ( model, Cmd.none )

        ApiNewNode groupId nodeId ->
            case
                List.Extra.find (\d -> d.id == nodeId)
                    model.nodes
            of
                Just node ->
                    let
                        groups =
                            case
                                List.Extra.find (\o -> o == groupId)
                                    node.groups
                            of
                                Just _ ->
                                    node.groups

                                Nothing ->
                                    groupId :: node.groups

                        -- optimistically update nodes
                        nodes =
                            List.map
                                (\d ->
                                    if d.id == node.id then
                                        { d | groups = groups }

                                    else
                                        d
                                )
                                model.nodes
                    in
                    ( { model | newNode = Nothing, nodes = nodes }
                    , Node.postGroups
                        { token = model.auth.token
                        , id = node.id
                        , groups = groups
                        , onResponse = ApiRespNewNode
                        }
                    )

                Nothing ->
                    ( { model | newNode = Nothing }, Cmd.none )

        ApiRespUpdate resp ->
            case resp of
                Data.Success _ ->
                    ( model
                    , Group.list { token = model.auth.token, onResponse = ApiRespList }
                    )

                Data.Failure err ->
                    ( popError "Error updating group" err model
                    , Group.list { token = model.auth.token, onResponse = ApiRespList }
                    )

                _ ->
                    ( model
                    , Group.list { token = model.auth.token, onResponse = ApiRespList }
                    )

        ApiRespDelete resp ->
            case resp of
                Data.Success _ ->
                    ( model, Cmd.none )

                Data.Failure err ->
                    ( popError "Error deleting group" err model
                    , Group.list { token = model.auth.token, onResponse = ApiRespList }
                    )

                _ ->
                    ( model
                    , Group.list { token = model.auth.token, onResponse = ApiRespList }
                    )

        ApiRespNewNode _ ->
            ( model, Cmd.none )

        ApiRespUserList resp ->
            case resp of
                Data.Success users ->
                    ( { model | users = users }, Cmd.none )

                Data.Failure err ->
                    ( popError "Error getting users" err model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ApiRespNodeList resp ->
            case resp of
                Data.Success nodes ->
                    ( { model | nodes = nodes }, Cmd.none )

                Data.Failure err ->
                    ( popError "Error getting nodes" err model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ApiRespList resp ->
            case resp of
                Data.Success groups ->
                    ( { model | groups = groups }, Cmd.none )

                Data.Failure err ->
                    ( popError "Error getting groups" err model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ApiRespGetUserByEmail resp ->
            case resp of
                Data.Success user ->
                    ( { model | newGroupUserFound = Just user }, Cmd.none )

                _ ->
                    ( { model | newGroupUserFound = Nothing }, Cmd.none )

        ApiRespGetNodeById resp ->
            case resp of
                Data.Success d ->
                    ( { model | newGroupNodeFound = Just d }, Cmd.none )

                _ ->
                    ( { model | newGroupNodeFound = Nothing }, Cmd.none )


popError : String -> Http.Error -> Model -> Model
popError desc err model =
    { model | error = Just (desc ++ ": " ++ Data.errorToString err) }


save : Model -> Shared.Model -> Shared.Model
save model shared =
    { shared
        | error =
            case model.error of
                Nothing ->
                    shared.error

                Just _ ->
                    model.error
        , lastError =
            case model.error of
                Nothing ->
                    shared.lastError

                Just _ ->
                    shared.now
    }


load : Shared.Model -> Model -> ( Model, Cmd Msg )
load _ model =
    ( { model | error = Nothing }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Document Msg
view model =
    { title = "SIOT Groups"
    , body =
        [ column
            [ width fill, spacing 32 ]
            [ el Style.h2 <| text "Groups"
            , el [ padding 16, width fill, Font.bold ] <|
                Form.button
                    { label = "new group"
                    , color = Style.colors.blue
                    , onPress = New
                    }
            , viewGroups model
            ]
        ]
    }


viewGroups : Model -> Element Msg
viewGroups model =
    column
        [ width fill
        , spacing 40
        ]
    <|
        List.map (\o -> viewGroup model o.mod o.group) <|
            mergeGroupEdit model.groups model.groupEdit


type alias GroupMod =
    { group : Group
    , mod : Bool
    }


mergeGroupEdit : List Group -> Maybe Group -> List GroupMod
mergeGroupEdit groups groupEdit =
    case groupEdit of
        Just edit ->
            let
                groupsMapped =
                    List.map
                        (\o ->
                            if edit.id == o.id then
                                { group = edit, mod = True }

                            else
                                { group = o, mod = False }
                        )
                        groups
            in
            if edit.id == "" then
                { group = edit, mod = True } :: groupsMapped

            else
                groupsMapped

        Nothing ->
            List.map (\o -> { group = o, mod = False }) groups


viewGroup : Model -> Bool -> Group -> Element Msg
viewGroup model modded group =
    let
        nodes =
            List.filter
                (\d ->
                    case List.Extra.find (\groupId -> group.id == groupId) d.groups of
                        Just _ ->
                            True

                        Nothing ->
                            False
                )
                model.nodes
    in
    column
        ([ width fill
         , Border.widthEach { top = 2, bottom = 0, left = 0, right = 0 }
         , Border.color Style.colors.black
         , spacing 6
         ]
            ++ (if modded then
                    [ Background.color Style.colors.orange
                    , below <|
                        Form.buttonRow
                            [ Form.button
                                { label = "save"
                                , color = Style.colors.blue
                                , onPress = ApiUpdate group
                                }
                            , Form.button
                                { label = "discard"
                                , color = Style.colors.gray
                                , onPress = DiscardGroupEdits
                                }
                            ]
                    ]

                else
                    []
               )
        )
        [ if group.id == "00000000-0000-0000-0000-000000000000" then
            el [ padding 16 ] (text group.name)

          else
            row
                []
                [ Form.viewTextProperty
                    { name = "Group name"
                    , value = group.name
                    , action = \x -> EditGroup { group | name = x }
                    }
                , Icon.x (ApiDelete group.id)
                ]
        , row []
            [ el [ padding 16, Font.italic, Font.color Style.colors.gray ] <| text "Users"
            , case model.newUser of
                Just newUser ->
                    if newUser.groupId == group.id then
                        Icon.x CancelAddUser

                    else
                        Icon.plus (AddUser group.id)

                Nothing ->
                    Icon.plus (AddUser group.id)
            ]
        , case model.newUser of
            Just ua ->
                if ua.groupId == group.id then
                    row []
                        [ Form.viewTextProperty
                            { name = "Enter new user email address"
                            , value = ua.userEmail
                            , action = \x -> EditNewUser x
                            }
                        , case model.newGroupUserFound of
                            Just user ->
                                Icon.plus (ApiNewUser group user.id)

                            Nothing ->
                                Element.none
                        ]

                else
                    Element.none

            Nothing ->
                Element.none
        , viewUsers group model.users
        , row []
            [ el [ padding 16, Font.italic, Font.color Style.colors.gray ] <| text "Nodes"
            , case model.newNode of
                Just newNode ->
                    if newNode.groupId == group.id then
                        Icon.x CancelAddNode

                    else
                        Icon.plus (AddNode group.id)

                Nothing ->
                    Icon.plus (AddNode group.id)
            ]
        , case model.newNode of
            Just nd ->
                if nd.groupId == group.id then
                    row []
                        [ Form.viewTextProperty
                            { name = "Enter new node ID"
                            , value = nd.nodeId
                            , action = \x -> EditNewNode x
                            }
                        , case model.newGroupNodeFound of
                            Just dev ->
                                Icon.plus (ApiNewNode group.id dev.id)

                            Nothing ->
                                Element.none
                        ]

                else
                    Element.none

            Nothing ->
                Element.none
        , viewNodes group nodes
        ]


viewUsers : Group -> List User -> Element Msg
viewUsers group users =
    column [ spacing 6, paddingEach { top = 0, right = 16, bottom = 0, left = 32 } ]
        (List.map
            (\ur ->
                case List.Extra.find (\u -> u.id == ur.userId) users of
                    Just user ->
                        row [ padding 16 ]
                            [ text
                                (user.first
                                    ++ " "
                                    ++ user.last
                                    ++ " <"
                                    ++ user.email
                                    ++ ">"
                                )
                            , Icon.x (ApiRemoveUser group user.id)
                            ]

                    Nothing ->
                        el [ padding 16 ] <| text "User not found"
            )
            group.users
        )


viewNodes : Group -> List Node -> Element Msg
viewNodes group nodes =
    column [ spacing 6, paddingEach { top = 0, right = 16, bottom = 0, left = 32 } ]
        (List.map
            (\d ->
                row [ padding 16 ]
                    [ text
                        ("("
                            ++ d.id
                            ++ ") "
                            ++ Node.description d
                        )
                    , Icon.x (ApiRemoveNode d.id group.id)
                    ]
            )
            nodes
        )
