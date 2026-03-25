defmodule Ancestry.Storage do
  @moduledoc """
  Handles storage of original uploaded files.

  In production (S3), uploads go directly to the configured S3 bucket.
  In development, files are stored on the local filesystem.
  """

  def store_original(tmp_path, dest_key) do
    contents = File.read!(tmp_path)

    case storage_backend() do
      Waffle.Storage.S3 ->
        ExAws.S3.put_object(bucket(), dest_key, contents)
        |> ExAws.request!()

        dest_key

      _ ->
        dest_path = Path.join(local_prefix(), dest_key)
        dest_path |> Path.dirname() |> File.mkdir_p!()
        File.write!(dest_path, contents)
        dest_path
    end
  end

  def fetch_original(original_path) do
    case storage_backend() do
      Waffle.Storage.S3 ->
        tmp_dir = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
        File.mkdir_p!(tmp_dir)
        tmp_path = Path.join(tmp_dir, Path.basename(original_path))

        %{body: contents} =
          ExAws.S3.get_object(bucket(), original_path)
          |> ExAws.request!()

        File.write!(tmp_path, contents)
        {:ok, tmp_path, tmp_dir}

      _ ->
        {:ok, original_path, nil}
    end
  end

  def cleanup_original(nil), do: :ok
  def cleanup_original(tmp_dir), do: File.rm_rf!(tmp_dir)

  def delete_original(original_path) do
    case storage_backend() do
      Waffle.Storage.S3 ->
        ExAws.S3.delete_object(bucket(), original_path)
        |> ExAws.request!()

        :ok

      _ ->
        :ok
    end
  end

  defp storage_backend, do: Application.get_env(:waffle, :storage)

  defp bucket do
    case Application.get_env(:waffle, :bucket) do
      {:system, env_var} -> System.get_env(env_var)
      bucket when is_binary(bucket) -> bucket
    end
  end

  defp local_prefix, do: Application.get_env(:waffle, :storage_dir_prefix, "priv/static")
end
