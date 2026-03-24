defmodule Joyconf.QRCode do
  def to_data_uri(url) do
    png_binary =
      url
      |> EQRCode.encode()
      |> EQRCode.png()
      |> IO.iodata_to_binary()

    "data:image/png;base64," <> Base.encode64(png_binary)
  end
end
