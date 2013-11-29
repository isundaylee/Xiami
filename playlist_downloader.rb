# encoding: utf-8

class PlaylistDownloader

  require_relative 'song_downloader'

  def self.combine_name(basename, counter)
    if counter == 0
      return basename
    else
      return basename + ' ' + counter.to_s
    end
  end

  def self.simplify_lyrics(l)
    ls = l.lines.to_a
    nls = []

    ls.each do |ll|
      unless ll =~ /\[[^0-9][^0-9]:.*?\]/
        ll.gsub! /\[.*?\]/, ''
        nls += [ll.strip]
      end
    end
    
    nls.join("\n")
  end

  def self.download(list, dir, lyrics_dir, cover, imported)
    require 'fileutils'

    `lock_acquire xiami_sync`

    return false unless `lock_check xiami_sync`.strip == 'true'

    trigger_file = "/tmp/xiami_sync.trigger"

    loop do 
      FileUtils.rm(trigger_file) if File.exists?(trigger_file)

      File.open("/tmp/xiami_sync.lock", 'w') do |lckf|

        unless lckf.flock(File::LOCK_NB | File::LOCK_EX)
          puts "已有同步进程执行中。"
          return false
        end

        puts "开始同步"

        songs = File.open(list) do |f|
          f.read.lines.select { |x| !x.strip.empty? }.map { |x| x.strip }.uniq.reverse
        end

        imp = File.open(imported) do |f|
          f.read.lines.select { |x| !x.strip.empty? }.map { |x| x.strip }
        end

        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        FileUtils.rm_rf(lyrics_dir)
        FileUtils.mkdir_p(lyrics_dir)

        songs.each do |s|
          next unless s.to_i > 0
          next if imported && imp.include?(s)

          info = SongDownloader.download_info(s)
          basename = "#{info.search('artist').text} - #{info.search('title').text}"
          counter = 0

          while File.exists?(File.join(dir, self.combine_name(basename, counter) + ".mp3")) do
            counter += 1
          end

          filename = "#{self.combine_name(basename, counter)}.mp3"
          lyrics_fn = "#{self.combine_name(basename, counter)}.lrc"
          puts "正在下载 #{filename}"
          SongDownloader.download(s, dir, info, filename)
          lyrics = SongDownloader.retrieve_lyrics(s, info)

          if !lyrics.strip.empty?
            File.open(File.join(lyrics_dir, lyrics_fn), 'w') { |f| f.write(lyrics) }
          end

          path = File.join(dir, filename)

          self.write_info(path, info, cover, simplify_lyrics(lyrics || ''))

          if imported && !imp.include?(s)
            self.import_to_itunes(path)
            imp += [s]
            File.open(imported, 'w') { |f| f.write(imp.join("\n")) }
            puts "已将 #{filename} 导入 iTunes"

            yield :imported, {id: s, filename: filename, info: info} if block_given?
          end
        end

        puts "同步完成"

      end

      break unless File.exists?(trigger_file)
    end

    `lock_release xiami_sync`

    return true

  end

  def self.import_to_itunes(path)
    require 'fileutils'
    itd = File.expand_path("~/Music/iTunes/iTunes Media/Automatically Add to iTunes.localized") 

    FileUtils.cp(path, itd)
  end

  def self.write_info(file, info, cover, lyrics = '')
    require 'taglib'

    TagLib::MPEG::File.open(file) do |f|
      tag = f.id3v2_tag

      tag.artist = info.search('artist').text
      tag.album = 'Favorites'
      tag.title = info.search('title').text

      tag.remove_frames('TCMP')
      t = TagLib::ID3v2::TextIdentificationFrame.new('TCMP', TagLib::String::UTF8)
      t.text = '1'
      tag.add_frame(t)

      unless lyrics.strip.empty? 
        tag.remove_frames('USLT')
        t = TagLib::ID3v2::UnsynchronizedLyricsFrame.new(TagLib::String::UTF8)
        t.text = lyrics
        tag.add_frame(t)
      end

      apic = TagLib::ID3v2::AttachedPictureFrame.new
      apic.mime_type = 'image/png'
      apic.description = 'Cover'
      apic.type = TagLib::ID3v2::AttachedPictureFrame::FrontCover
      apic.picture = File.open(cover, 'rb') { |f| f.read }

      tag.add_frame(apic)

      f.save
    end
  end

end

