#!/usr/bin/env ruby

require 'chronic'
require 'exiftool'
require 'mini_magick'
require 'rickshaw'

FOLDERS = [
  '.',
]

EXTENSIONS = %r{\A(\.jpg|\.nef)\z}i

PROCESSED_FILENAME = File.expand_path('./processed.txt', __dir__)

TARGET_FOLDER = File.expand_path('~/processed_photos')

class Photo
  attr_accessor \
    :filename,
    :target_filename

  def self.photo?(filename)
    EXTENSIONS.match(File.extname(filename))
  end

  def self.all
    FOLDERS.map do |folder|
      Dir.glob(File.join(folder, '**/*'))
    end.flatten.select do |filename|
      photo?(filename)
    end.map do |filename|
      new(filename)
    end
  end

  def self.not_processed_yet
    all.reject do |photo|
      photo.processed? || photo.already_exists_in_processed?
    end
  end

  def self.process
    not_processed_yet.map do |photo|
      photo.process
    end
  end

  def self.processed_digests
    return [] unless File.exist?(PROCESSED_FILENAME)

    File.open(PROCESSED_FILENAME).read().split do |line|
      line.split(':').first
    end.reject do |line|
      line.empty?
    end
  end

  def initialize(filename)
    @filename = filename
  end

  def digest
    Rickshaw::SHA256.hash(filename)
  end

  def processed?
    Photo.processed_digests.include?(digest)
  end

  def already_exists_in_processed?
    File.exist?(target_filename)
  end

  def process
    convert_or_copy

    record_in_processed
  end

  def basename
    File.basename(filename, extension)
  end

  def basename_with_datetime
    datetime.strftime("photo-%Y%m%d-%H%M%S")
  end

  def extension
    File.extname(filename)
  end

  def target_filename
    File.join(TARGET_FOLDER, basename_with_datetime + '.jpg')
  end

  def jpg?
    extension.downcase == '.jpg'
  end

  def metadata
    exif = Exiftool.new(filename)
    exif.to_hash
  end

  def date_time_original
    metadata[:date_time_original]
  end

  def datetime
    Chronic.parse(date_time_original)
  end

  def convert_or_copy
    if jpg?
      FileUtils.copy_file(filename, target_filename)
    else
      convert
    end
  end

  def convert
    return if jpg?

    image = MiniMagick::Image.open(filename)

    image.format('jpg')
    image.write(target_filename)

    `exiftool -tagsFromFile #{filename} #{target_filename}`
  end

  def record_in_processed
    File.open(PROCESSED_FILENAME, 'a') do |writer|
      writer.write([digest, filename].join(':') + "\n")
    end
  end
end

def ensure_target_folder
  Dir.mkdir(TARGET_FOLDER) unless Dir.exist?(TARGET_FOLDER)
end

def main
  ensure_target_folder

  Photo.process
end

main
