-module(rebar_app_discover).

-export([do/2,
         find_unbuilt_apps/1,
         find_apps/1,
         find_apps/2,
         find_app/2,
         validate_application_info/1]).

do(State, LibDirs) ->
    BaseDir = rebar_state:dir(State),
    Dirs = [filename:join(BaseDir, LibDir) || LibDir <- LibDirs],
    Apps = find_apps(Dirs, all),
    ProjectDeps = rebar_state:deps_names(State),
    lists:foldl(fun(AppInfo, StateAcc) ->
                        ProjectDeps1 = lists:delete(rebar_app_info:name(AppInfo), ProjectDeps),
                        rebar_state:project_apps(StateAcc, rebar_app_info:deps(AppInfo, ProjectDeps1))
            end, State, Apps).

-spec all_app_dirs(list(file:name())) -> list(file:name()).
all_app_dirs(LibDirs) ->
    lists:flatmap(fun(LibDir) ->
                          app_dirs(LibDir)
                  end, LibDirs).

app_dirs(LibDir) ->
    Path1 = filename:join([LibDir,
                           "*",
                           "src",
                           "*.app.src"]),
    Path2 = filename:join([LibDir,
                           "src",
                           "*.app.src"]),

    Path3 = filename:join([LibDir,
                           "*",
                           "ebin",
                           "*.app"]),
    Path4 = filename:join([LibDir,
                           "ebin",
                           "*.app"]),

    lists:usort(lists:foldl(fun(Path, Acc) ->
                                    Files = filelib:wildcard(ec_cnv:to_list(Path)),
                                    [app_dir(File) || File <- Files] ++ Acc
                            end, [], [Path1, Path2, Path3, Path4])).

find_unbuilt_apps(LibDirs) ->
    find_apps(LibDirs, invalid).

-spec find_apps([file:filename_all()]) -> [rebar_app_info:t()].
find_apps(LibDirs) ->
    find_apps(LibDirs, valid).

-spec find_apps([file:filename_all()], valid | invalid | all) -> [rebar_app_info:t()].
find_apps(LibDirs, Validate) ->
    rebar_utils:filtermap(fun(AppDir) ->
                                  find_app(AppDir, Validate)
                          end, all_app_dirs(LibDirs)).

-spec find_app(file:filename_all(), valid | invalid | all) -> {true, rebar_app_info:t()} | false.
find_app(AppDir, Validate) ->
    AppFile = filelib:wildcard(filename:join([AppDir, "ebin", "*.app"])),
    AppSrcFile = filelib:wildcard(filename:join([AppDir, "src", "*.app.src"])),
    case AppFile of
        [File] ->
            AppInfo = create_app_info(AppDir, File),
            AppInfo1 = rebar_app_info:app_file(AppInfo, File),
            AppInfo2 = case AppSrcFile of
                           [F] ->
                               rebar_app_info:app_file_src(AppInfo1, F);
                           [] ->
                               AppInfo1;
                           Other when is_list(Other) ->
                               throw({error, {multiple_app_files, Other}})
                       end,
            case Validate of
                valid ->
                    case validate_application_info(AppInfo2) of
                        true ->
                            {true, AppInfo2};
                        false ->
                            false
                    end;
                invalid ->
                    case validate_application_info(AppInfo2) of
                        false ->
                            {true, AppInfo2};
                        true ->
                            false
                    end;
                all ->
                    {true, AppInfo2}
            end;
        [] ->
            case AppSrcFile of
                [File] ->
                    case Validate of
                        V when V =:= invalid ; V =:= all ->
                            AppInfo = create_app_info(AppDir, File),
                            {true, rebar_app_info:app_file_src(AppInfo, File)};
                        valid ->
                            false
                    end;
                [] ->
                    false;
                Other when is_list(Other) ->
                    throw({error, {multiple_app_files, Other}})
            end;
        Other when is_list(Other) ->
            throw({error, {multiple_app_files, Other}})
    end.

app_dir(AppFile) ->
    filename:join(rebar_utils:droplast(filename:split(filename:dirname(AppFile)))).

-spec create_app_info(file:name(), file:name()) -> rebar_app_info:t() | error.
create_app_info(AppDir, AppFile) ->
    case file:consult(AppFile) of
        {ok, [{application, AppName, AppDetails}]} ->
            AppVsn = proplists:get_value(vsn, AppDetails),
            Applications = proplists:get_value(applications, AppDetails, []),
            IncludedApplications = proplists:get_value(included_applications, AppDetails, []),
            {ok, AppInfo} = rebar_app_info:new(AppName, AppVsn, AppDir, []),
            AppInfo1 = rebar_app_info:applications(
                         rebar_app_info:app_details(AppInfo, AppDetails),
                         IncludedApplications++Applications),
            rebar_app_info:dir(AppInfo1, AppDir);
        _ ->
            error
    end.

-spec validate_application_info(rebar_app_info:t()) -> boolean().
validate_application_info(AppInfo) ->
    EbinDir = rebar_app_info:ebin_dir(AppInfo),
    case rebar_app_info:app_file(AppInfo) of
        undefined ->
            false;
        AppFile ->
            AppDetail = rebar_app_info:app_details(AppInfo),
            case get_modules_list(AppFile, AppDetail) of
                {ok, List} ->
                    has_all_beams(EbinDir, List);
                _Error ->
                    false
            end
    end.

-spec get_modules_list(file:filename_all(), proplists:proplist()) ->
                              {ok, list()} |
                              {warning, Reason::term()} |
                              {error, Reason::term()}.
get_modules_list(AppFile, AppDetail) ->
    case proplists:get_value(modules, AppDetail) of
        undefined ->
            {warning, {invalid_app_file, AppFile}};
        ModulesList ->
            {ok, ModulesList}
    end.

-spec has_all_beams(file:filename_all(), list()) -> boolean().
has_all_beams(EbinDir, [Module | ModuleList]) ->
    BeamFile = filename:join([EbinDir,
                              ec_cnv:to_list(Module) ++ ".beam"]),
    case filelib:is_file(BeamFile) of
        true ->
            has_all_beams(EbinDir, ModuleList);
        false ->
            false
    end;
has_all_beams(_, []) ->
    true.
