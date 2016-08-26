defmodule ExACN.PDU do
  defstruct vector: <<>>, header: <<>>, data: <<>>

  defp build_body(pdu, nil) do
    pdu.vector <> pdu.header <> pdu.data
  end

  defp build_body(pdu, previous) do
    [:vector, :header, :data]
    |> Enum.map(fn field -> {Map.get(pdu, field), Map.get(previous, field)} end)
    |> Enum.filter(fn {current, previous} -> current != previous end)
    |> Enum.map(fn {current, _} -> current end)
    |> Enum.join
  end

  defp length_bits(length_flag) do
    case length_flag do
      1 -> 20
      0 -> 12
    end
  end

  defp preamble_bytes(length_flag) do
    case length_flag do
      1 -> 3
      0 -> 2
    end
  end

  def pack(pdu, previous) do
    vector_flag = if previous != nil && pdu.vector == previous.vector, do: 1, else: 0
    header_flag = if previous != nil && pdu.header == previous.header, do: 1, else: 0
    data_flag = if previous != nil && pdu.data == previous.data, do: 1, else: 0

    body = build_body(pdu, previous)

    length = byte_size(body)
    length_flag = if length > round(:math.pow(2, 12)) - 3, do: 1, else: 0 # less one for binary encoding and two for the preamble

    flags = << length_flag :: size(1), vector_flag :: size(1), header_flag :: size(1), data_flag :: size(1) >>

    encoded_length_bits = length_bits(length_flag)
    encoded_length = length + preamble_bytes(length_flag)

    << flags::bits, encoded_length::size(encoded_length_bits), body::bytes>>
  end

  def extract_vector(body, 1, _, _, previous) do
    {previous.vector, body}
  end

  def extract_vector(body, 0, length, vec_length, _) do
    header_and_data_length = length - vec_length
    << vector::binary-size(vec_length), header_and_data::binary-size(header_and_data_length) >> = body
    {vector, header_and_data}
  end

  def extract_header_and_data(header_and_data, _, header_length, 0, 0) do
    header_size = header_length.(header_and_data)
    << header::binary-size(header_size), data::binary >> = header_and_data
    {header, data}
  end

  def extract_header_and_data(header_and_data, previous, _, 1, 0) do
    {header_and_data, previous.data}
  end

  def extract_header_and_data(header_and_data, previous, _, 0, 1) do
    { previous.header, header_and_data }
  end

  def extract_header_and_data(_, previous, _, 1, 1) do
    { previous.header, previous.data }
  end

  def unpack(encoded, previous, vec_length, header_length) when is_integer(header_length) do
    unpack(encoded, previous, vec_length, fn _ -> header_length end)
  end

  def unpack(encoded, previous, vec_length, header_length) do
    <<length_flag::size(1), vector_flag::size(1), header_flag::size(1), data_flag::size(1), _::bits >> = encoded
    length_bits_encoded = length_bits(length_flag)
    << _::bits-size(4), length::size(length_bits_encoded), _::binary >> = encoded
    preamble_bytes_encoded = preamble_bytes(length_flag)
    body_bytes = length - preamble_bytes_encoded
    << _::bytes-size(preamble_bytes_encoded), body::binary-size(body_bytes), tail::binary >> = encoded

    {vector, header_and_data} = extract_vector(body, vector_flag, body_bytes, vec_length, previous)


    {header, data} = extract_header_and_data(header_and_data, previous, header_length, header_flag, data_flag)

    pdu = %ExACN.PDU{vector: vector, header: header, data: data}


    {:ok, pdu, tail}
  end
end
