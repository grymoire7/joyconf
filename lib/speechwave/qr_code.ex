defmodule Speechwave.QRCode do
  @moduledoc """
  Generates QR codes as base64-encoded PNG data URIs.

  Wraps the `EQRCode` library. The output of `to_data_uri/1` can be used
  directly in an `<img src={...}>` tag without a separate HTTP request or
  file on disk.
  """
  def to_data_uri(url) do
    png_binary =
      url
      |> EQRCode.encode()
      |> EQRCode.png()
      |> IO.iodata_to_binary()

    "data:image/png;base64," <> Base.encode64(png_binary)
  end
end
