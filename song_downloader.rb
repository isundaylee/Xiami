# encoding: utf-8

class SongDownloader
  require_relative 'location_decoder'  

  INFO_URL = 'http://www.xiami.com/song/playlist/id/%d/object_name/default/object_id/0'
  CACHE_DIR = 'cache'

  def self.download_info(id)
    require 'open-uri'
    require 'nokogiri'

    info_url = INFO_URL % id

    self.download_to_cache(info_url, "#{id}.info")

    Nokogiri::XML(File.open(self.cache_path("#{id}.info")).read)
  end

  def self.download_to_cache(url, filename, hidden = true)
    ccp = File.join(File.expand_path(CACHE_DIR), filename + ".tmp")
    cfp = File.join(File.expand_path(CACHE_DIR), filename)

    if !File.exists?(cfp)
      FileUtils.rm_rf(ccp)
      command = "curl --retry 999 --retry-max-time 0 -C - -# \"#{url}\" -o \"#{ccp}\""
      command += " > /dev/null 2>&1" if hidden
      system(command)
      FileUtils.mv(ccp, cfp)
    end
  end

  def self.cache_path(filename)
    File.join(File.expand_path(CACHE_DIR), filename)
  end

  def self.download(id, out, info = nil, filename = nil)
    require 'fileutils'

    filename ||= "#{id}.mp3"

    FileUtils.mkdir_p(File.expand_path(out))
    otp = File.join(File.expand_path(out), filename)

    if !File.exists?(self.cache_path("#{id}.mp3"))

      info ||= self.download_info(id)
      url = LocationDecoder.decode(info.search('location').text)

      self.download_to_cache(url, "#{id}.mp3", false)

    end

    FileUtils.rm_f(otp)
    FileUtils.cp(self.cache_path("#{id}.mp3"), otp)

  end

  def self.retrieve_lyrics(id, info = nil)
    require 'open-uri'

    info ||= self.download_info(id)

    if info.search('lyric') && !info.search('lyric').text.strip.empty?
      self.download_to_cache(info.search('lyric').text, "#{id}.lrc")
      return File.open(self.cache_path("#{id}.lrc")).read
    else
      return ''
    end
  end
end
