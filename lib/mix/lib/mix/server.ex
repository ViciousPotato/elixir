defmodule Mix.Server do
  @moduledoc false
  use GenServer.Behaviour

  defrecord Config, tasks: :ordsets.new, projects: [], mixfile: [],
    shell: Mix.Shell.IO, scm: :ordsets.new, env: nil, post_config: []

  defrecord Project, name: nil, config: nil, rec_enabled?: true, io_done: false, file: nil

  def start_link(env) do
    :gen_server.start_link({ :local, __MODULE__ }, __MODULE__, env, [])
  end

  def call(arg) do
    :gen_server.call(__MODULE__, arg, 30_000)
  end

  def cast(arg) do
    :gen_server.cast(__MODULE__, arg)
  end

  ## Callbacks

  def init(env) do
    { :ok, Config[env: env] }
  end

  def handle_call(:tasks, _from, config) do
    { :reply, config.tasks, config }
  end

  def handle_call(:projects, _from, config) do
    { :reply, config.projects, config }
  end

  def handle_call(:shell, _from, config) do
    { :reply, config.shell, config }
  end

  def handle_call(:scm, _from, config) do
    { :reply, config.scm, config }
  end

  def handle_call(:env, _from, config) do
    { :reply, config.env, config }
  end

  def handle_call(:clear_tasks, _from, config) do
    { :reply, config.tasks, config.tasks(:ordsets.new) }
  end

  def handle_call({ :has_task?, task, app }, _from, config) do
    { :reply, :ordsets.is_element({task, app}, config.tasks), config }
  end

  def handle_call(:pop_project, _from, config) do
    case config.projects do
      [ Project[name: name, file: file] | tail ] ->
        { :reply, { name, file }, config.projects(tail) }
      _ ->
        { :reply, nil, config }
    end
  end

  def handle_call({ :mixfile_cache, app }, _from, config) do
    { :reply, config.mixfile[app], config }
  end

  def handle_call(:output_app?, _from, config) do
    # Check that we haven't already outputted app and that we are part of an
    # umbrella project
    case config.projects do
      [ project | tail ] ->
        output = not project.io_done and not umbrella?(config) and in_umbrella?(config)
        { :reply, output, config.projects([project.io_done(true)|tail]) }
      _ ->
        { :reply, false, config }
    end
  end

  def handle_call(:recursive_enabled?, _from, config) do
    case config.projects do
      [ Project[rec_enabled?: bool] | _ ] ->
        { :reply, bool, config }
      _ ->
        { :reply, false, config }
    end
  end

  def handle_call({ :push_project, name, config, file }, _from, state) do
    config  = Keyword.merge(config, state.post_config)
    project = Project[name: name, config: config, file: file]

    cond do
      file = has_project_named(name, state) ->
        { :reply, { :error, file }, state }
      true ->
        { :reply, :ok, state.post_config([]).update_projects(&[project|&1]) }
    end
  end

  def handle_call(request, from, config) do
    super(request, from, config)
  end

  defp has_project_named(name, state) do
    name && Enum.find_value(state.projects, fn
      Project[name: ^name, file: file] -> file
      Project[] -> nil
    end)
  end

  def handle_cast({ :shell, name }, config) do
    { :noreply, config.shell(name) }
  end

  def handle_cast({ :env, env }, config) when is_atom(env) do
    { :noreply, config.env(env) }
  end

  def handle_cast({ :add_task, task, app }, config) do
    { :noreply, config.update_tasks &:ordsets.add_element({task, app}, &1) }
  end

  def handle_cast({ :delete_task, task, app }, config) do
    { :noreply, config.update_tasks &:ordsets.del_element({task, app}, &1) }
  end

  def handle_cast({ :delete_task, task }, config) do
    { :noreply, config.update_tasks &:ordsets.filter(fn {t, _} -> t != task end, &1) }
  end

  def handle_cast({ :post_config, value }, config) do
    { :noreply, config.update_post_config(&Keyword.merge(&1, value)) }
  end

  def handle_cast({ :add_scm, mod }, config) do
    { :noreply, config.update_scm &:ordsets.add_element(mod, &1) }
  end

  def handle_cast({ :mixfile_cache, app, new }, config) do
    { :noreply, config.update_mixfile(&Keyword.merge(&1, [{ app, new }])) }
  end

  def handle_cast(:clear_mixfile_cache, config) do
    { :noreply, config.mixfile([]) }
  end

  def handle_cast({:recursive_enabled?, bool}, config) do
    case config.projects do
      [ project | tail ] ->
        { :noreply, config.projects([project.rec_enabled?(bool)|tail]) }
      _ ->
        { :noreply, config }
    end
  end

  def handle_cast(request, config) do
    super(request, config)
  end

  # Returns true if project is part of an umbrella project
  defp in_umbrella?(config) do
    Enum.any?(config.projects, fn(Project[config: conf]) ->
      conf[:apps_path] != nil
    end)
  end

  # Returns true if project is an umbrella project
  defp umbrella?(config) do
    case config.projects do
      [ Project[name: name, config: config] | _ ] when name != nil ->
        config[:apps_path] != nil
      _ -> false
    end
  end
end
