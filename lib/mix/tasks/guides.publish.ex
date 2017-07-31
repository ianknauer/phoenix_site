defmodule Mix.Tasks.Guides.Publish do
  use Mix.Task

  @bucket "phoenixframework.org"
  @blog_prefix "build/blog--"

  @doc "Publishes guides to S3"

  def run([]) do
    build_local_files()

    []
    |> minify_css()
    |> copy_assets()
    |> copy_index_files()
    |> copy_blog_files()
    |> Enum.map(&Task.await(&1, :infinity))
  end

  defp build_local_files do
    log "obelisk: building static files"
    Mix.Task.run("obelisk", ["build"])
  end

  defp minify_css(tasks) do
    async(tasks, fn ->
      purify = System.cmd("purifycss", ["build/assets/css/base.css",
                                        "build/*.html"])

      case purify do
        {output, 0} -> File.write!("build/assets/css/base.css", output)
        _ -> nil
      end
    end)
  end

  defp copy_assets(tasks) do
    async(tasks, fn->
      log "s3: copying assets"
      System.cmd("aws",
        ~w(s3 cp build/assets s3://#{@bucket}/assets --acl public-read --recursive))
      System.cmd("aws",
        ~w(s3 cp build/assets/favicon.ico s3://#{@bucket}/favicon.ico --acl public-read))
    end)
  end

  defp copy_index_files(tasks) do
    "build/*.{html,rss}"
    |> Path.wildcard()
    |> Enum.reduce(tasks, fn name, acc ->
      log "s3: copying index file #{name}"
      async(acc, fn ->
        s3_cp(name, Path.basename(name, ".html"), Path.extname(name))
      end)
    end)
  end

  defp copy_blog_files(tasks) do
    (@blog_prefix <> "*")
    |> Path.wildcard()
    |> Enum.reduce(tasks, fn @blog_prefix <> name = full_name, acc ->
      async(acc, fn ->
        basename = Path.basename(name, ".html")

        log "s3: publishing blog/#{basename}"
        s3_cp(full_name, "blog/#{basename}", ".html")
      end)
    end)
  end

  defp async(tasks, task) do
    [Task.async(task) | tasks]
  end

  defp s3_cp(name, s3_path, ".html") do
    System.cmd("aws", ["s3", "cp", name,
                       "s3://#{@bucket}/#{s3_path}",
                       "--content-type","text/html",
                       "--acl", "public-read"])
  end
  defp s3_cp(name, s3_path, _ext) do
    System.cmd("aws", ["s3", "cp", name,
                       "s3://#{@bucket}/#{s3_path}",
                       "--acl", "public-read"])
  end

  defp log(msg) do
    IO.puts ">> #{msg}"
  end
end
