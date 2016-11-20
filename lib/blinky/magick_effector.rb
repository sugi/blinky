require 'blinky/version'
require 'blinky/request'
require 'rmagick'

module Blinky
  module MagickEffector
    module_function

    def metadata(m_img, metadata = {})
      {
        'Software'           => 'Blinky',
        'Blinky::Version'   => Blinky::VERSION,
        'Blinky::Timestamp' => Time.now.to_i,
      }.merge(metadata).each do |key, val|
        m_img[key] = val.to_s
      end
      m_img
    end

    def resize(m_img, width, height)
      m_img.columns == width && m_img.rows == height and return m_img
      m_img.resize(width, height)
    end

    def shadow(m_img)
      m_img.background_color = '#333'
      shadow = m_img.shadow(0, 0, [m_img.columns * 0.015, 16].min, 0.6)
      shadow.background_color = '#FEFEFE'
      shadow.composite!(m_img, Magick::CenterGravity, Magick::OverCompositeOp)
      m_img.destroy!
      shadow
    end

    def gen_waitimage(req)
      img = gen_emptyimage(req.imgsize_x, req.imgsize_y)
      img = metadata(img, 'Blinky::URI' => req.uri)
      gc = Magick::Draw.new
      gc.stroke('transparent')
      gc.font_family('times')
      gc.pointsize(15)
      gc.text_align(Magick::RightAlign)
      gc.font_weight(Magick::BoldWeight)
      gc.fill('#CCCCCC')
      gc.text(req.imgsize_x - 5, req.imgsize_y - 21, 'Now')
      gc.text(req.imgsize_x - 5, req.imgsize_y - 5, 'Printing')
      gc.draw(img)
      req.effect and
        img = shadow(img)
      img.format='png'
      img
    end

    def gen_waitimage_blob(req)
      img = gen_waitimage(req)
      blob = img.to_blob
      img.destroy!
      blob
    end

    def gen_failimage(req)
      img = gen_emptyimage(req.imgsize_x, req.imgsize_y)
      img = metadata(img, 'Blinky::URI' => req.uri)
      gc = Magick::Draw.new
      gc.stroke('transparent')
      gc.font_family('times')
      gc.pointsize(16)
      gc.text_align(Magick::RightAlign)
      gc.font_weight(Magick::BoldWeight)
      gc.fill('#FFA0A0')
      gc.text(req.imgsize_x - 5, req.imgsize_y - 5, 'Error...')
      gc.draw(img)
      req.effect and
        img = shadow(img)
      img.format = 'png'
      img
    end

    def gen_failimage_blob(req)
      img = gen_failimage(req)
      blob = img.to_blob
      img.destroy!
      blob
    end

    def gen_emptyimage(width, height)
      Magick::Image.new(width, height) {
        self.background_color = 'white'
      }
    end

    def all(m_img, req)
      m_img = metadata(m_img, 'Blinky::URI' => req.uri)
      req.effect and
        m_img = shadow(m_img)
      ret = resize(m_img, req.real_imgsize_x, req.real_imgsize_y)
      m_img.destroy!
      ret
    end
  end
end
