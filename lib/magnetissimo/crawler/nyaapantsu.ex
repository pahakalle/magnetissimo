defmodule Magnetissimo.Crawler.NyaaPantsu do
  @moduledoc """
  Torrent parser for Nyaa.si in charge of scraping and saving
  the latest torrents on the website.
  """

  @behaviour Magnetissimo.RSSParser
  use GenServer
  require Logger

  def initial_queue do
    categories = [
      '1_', # Software
      '2_', # Audio
      '3_', # Anime
      '4_', # Literature
      '5_', # Live Action
      '6_', # Pictures
    ]
    urls = for category <- categories do
      {:page_link, "https://nyaa.pantsu.cat/feed/eztv?c=#{category}"}
    end

    # # Uncomment this section to scrape NSFW content
    # nsfw_categories = [
    #   '1_1', # Art/Anime
    #   '1_2', # Art/Doujinshi
    #   '1_3', # Art/Games
    #   '1_4', # Art/Manga
    #   '1_5', # Art/Picture
    #   '2_', # Real Life
    # ]
    # nsfw_urls = for category <- nsfw_categories do
    #   {:page_link, "https://sukebei.pantsu.cat/feed/eztv?c=#{category}"}
    # end
    # urls = Enum.concat(urls, nsfw_urls)

    :queue.from_list(urls)
  end

  def start_link(_) do
    queue = initial_queue()
    GenServer.start_link(__MODULE__, queue, name: __MODULE__)
  end

  def init(queue) do
    Logger.info IO.ANSI.magenta <> "Starting NyaaPantsu crawler" <> IO.ANSI.reset
    schedule_work()
    {:ok, queue}
  end

  defp schedule_work do
    wait = 1800000 # 30mn wait so we don't hammer the site too hard
    Process.send_after(self(), :work, wait)
  end

  def handle_info(:work, queue) do
    new_queue =
      case :queue.out(queue) do
        {{_value, item}, queue_2} ->
          process(item, queue_2)
      _ ->
        wait_seconds = 10 * 1000 # 10 second wait so we don't hammer the site too hard
        :timer.sleep(wait_seconds)
        Logger.info "[NyaaPantsu] Queue is empty, restarting scraping procedure."
        initial_queue()
    end
    schedule_work()
    {:noreply, new_queue}
  end

  def process({:page_link, url}, queue) do
    Logger.info "[NyaaPanstu] Downloading torrents from page: #{url}"
    with {:ok, body} <- Magnetissimo.Crawler.Helper.download(url),
         torrent_list when is_list(torrent_list )<- torrent_information(body) do
          for torrent <- torrent_list do
            Magnetissimo.Torrent.save_torrent(torrent)
          end
    else
      {:error, message} ->
        Logger.error message
    end
    queue
  end

  defp item_to_map(item) do
    name = item
      |> Floki.find("title")
      |> Floki.text

    magnet = item
      |> Floki.find("torrent > magneturi")
      |> Floki.text

    size = item
      |> Floki.find("torrent > contentlength")
      |> Floki.text

    outbound_url = item
      |> Floki.find("guid")
      |> Floki.text

    %{
      name: name,
      magnet: magnet,
      size: size,
      website_source: "nyaapantsu",
      seeders: 0,
      leechers: 0,
      outbound_url: outbound_url,
    }
  end

  def torrent_information(rss_body) when is_binary(rss_body) and byte_size(rss_body) > 50 do
    items = rss_body
      |> Floki.find("channel > item")

    maps = for item <- items do
      item_to_map(item)
    end
    maps
  end

  def torrent_information(_rss_body) do
    {:error, "Couldn't read rss feed"}
  end

end
