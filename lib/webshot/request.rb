require 'webshot/version'
require 'webshot/errors'
require 'webshot/utils'
require 'digest/sha1'
require 'digest/md5'

module WebShot
  class Request
    def self.from_cgi(cgi)
      if !cgi['uri'].empty?
        from_cgi_standard(cgi)
      else
        from_cgi_pathinfo(cgi)
      end
    end

    def self.from_cgi_standard(cgi)
      args = {}
      args[:uri] = cgi.params['uri'][0]

      wx, wy, ix, iy = cgi['win_x'], cgi['win_y'], cgi['img_x'], cgi['img_y']

      winsize = []
      !wx.empty? && wx.to_i != 0 and winsize[0] = wx.to_i
      !wy.empty? && wy.to_i != 0 and winsize[1] = wy.to_i
      winsize[1] and winsize[0] ||= winsize[1]
      winsize[0] and winsize[1] ||= winsize[0]
      !winsize.empty? and args[:winsize] = winsize

      if cgi.params['noresize'][0] == "true"
        args[:imgsize] = args[:winsize]
      else
        imgsize = []
        !ix.empty? && ix.to_i != 0 and imgsize[0] = ix.to_i
        !iy.empty? && iy.to_i != 0 and imgsize[1] = iy.to_i
        imgsize[1] and imgsize[0] ||= imgsize[1]
        imgsize[0] and imgsize[1] ||= imgsize[0]
        !imgsize.empty? and args[:imgsize] = imgsize
      end

      args[:keepratio] = cgi.params['keepratio'][0] == "true"  ? true : false
      args[:effect]    = cgi.params['effect'][0]    != "false" ? true : false

      new args
    end

    def self.from_cgi_pathinfo(cgi)
      args = {}
      args[:uri] = cgi.query_string

      case cgi.path_info
      when %r[^/xlarge/?]
        args[:imgsize] = [512, 512]
      when %r[^/large/?]
        args[:imgsize] = [256, 256]
      when %r[^/small/?]
        args[:imgsize] = [64, 64]
      when %r[^/(?:(\d+)x(\d+))?(?:-(\d+)x(\d+))?]
        $1.to_i != 0 && $2.to_i != 0 and args[:imgsize] = [$1.to_i, $2.to_i]
        if $3.to_i != 0 && $4.to_i != 0
          args[:winsize] = [$3.to_i, $4.to_i]
        elsif args[:imgsize]
          args[:winsize][1] = (args[:winsize][0].to_f * args[:imgsize][1] / args[:imgsize][0]).to_i
          args[:keepratio] = false
        end
      end

      new args
    end

    def self.from_rack(rreq, rparams)
      if rparams.keys.find {|k| k =~ /^https?:/ }
        from_rack_pathinfo rreq, rparams
      else
        from_rack_params rreq, rparams
      end
    end

    def self.from_rack_params(rreq, rparams)
      args = {}
      args[:uri] = rparams['uri']

      wx, wy, ix, iy = rparams['win_x'], rparams['win_y'], rparams['img_x'], rparams['img_y']

      winsize = []
      wx.to_i != 0 and winsize[0] = wx.to_i
      wy.to_i != 0 and winsize[1] = wy.to_i
      winsize[1] and winsize[0] ||= winsize[1]
      winsize[0] and winsize[1] ||= winsize[0]
      !winsize.empty? and args[:winsize] = winsize

      if rparams['noresize'] == "true"
        args[:imgsize] = args[:winsize]
      else
        imgsize = []
        ix.to_i != 0 and imgsize[0] = ix.to_i
        iy.to_i != 0 and imgsize[1] = iy.to_i
        imgsize[1] and imgsize[0] ||= imgsize[1]
        imgsize[0] and imgsize[1] ||= imgsize[0]
        !imgsize.empty? and args[:imgsize] = imgsize
      end

      args[:keepratio] = rparams['keepratio'] == "true"  ? true : false
      args[:effect]    = rparams['effect']    != "false" ? true : false

      new args
    end

    def self.from_rack_pathinfo(rreq, rparams)
      args = {}
      args[:uri] = rreq.query_string

      case rparams['splat'].to_a.first
      when %r[^xlarge/?]
        args[:imgsize] = [512, 512]
      when %r[^large/?]
        args[:imgsize] = [256, 256]
      when %r[^small/?]
        args[:imgsize] = [64, 64]
      when %r[^(?:(\d+)x(\d+))?(?:-(\d+)x(\d+))?]
        $1.to_i != 0 && $2.to_i != 0 and args[:imgsize] = [$1.to_i, $2.to_i]
        if $3.to_i != 0 && $4.to_i != 0
          args[:winsize] = [$3.to_i, $4.to_i]
        elsif args[:imgsize]
          args[:winsize] = [1280, (1280.0 * args[:imgsize][1] / args[:imgsize][0]).to_i]
          args[:keepratio] = false
        end
      end

      new args
    end

    def initialize(args = {})
      @uri = nil
      @imgsize_x = 128
      @imgsize_y = 128
      @winsize_x = 1280
      @winsize_y = 1280
      @keepratio = true
      @effect = true

      args.each do |key, val|
        self.public_send "#{key}=", val
      end
    end
    attr_accessor :uri, :imgsize_x, :imgsize_y, :winsize_x, :winsize_y, :keepratio, :effect

    def ident
      Digest::SHA1.hexdigest([winsize, imgsize, effect, keepratio, uri].flatten.join(','))
    end

    def legacy_ident
      Digest::MD5.hexdigest([req.winsize,
                              req.imgsize,
                              req.effect,
                              req.uri].flatten.join(",")) +
        ".#{req.uri[req.uri.length/2, 4].unpack('H*').join}" +
        "-#{req.uri.length}"
    end

    def imgsize
      [imgsize_x, imgsize_y]
    end

    def winsize
      [winsize_x, winsize_y]
    end

    def imgsize=(v)
      v = [*v]
      v.length < 2 and v[1] = v[0]
      @imgsize_x = v[0]
      @imgsize_y = v[1]
      imgsize
    end

    def winsize=(v)
      v = [*v]
      v.length < 2 and v[1] = v[0]
      @winsize_x = v[0]
      @winsize_y = v[1]
      winsize
    end

    def real_imgsize_x
      real_imgsize[0]
    end

    def real_imgsize_y
      real_imgsize[1]
    end

    def real_imgsize
      keepratio or return imgsize

      width, height = *imgsize

      ratio = winsize_x.to_f / winsize_y
      if width.to_i.zero? || !height.to_i.zero? && height * ratio < width
        width  = height * ratio
      elsif height.to_i.zero? || !width.to_i.zero? && width / ratio < height
        height = width / ratio
      end

      [width, height]
    end

    def validate!
      if uri.nil? || uri.empty? || uri !~ %r{^https?://[^.]+\.[^.]+}
        raise InvalidURI.new("Invalid URI: '#{uri}'")
      end
      if config.forbidden_url_pattern &&
          config.forbidden_url_pattern.match(uri.to_s)
        raise ForbiddenURI.new("Forbidden URI: '#{uri}'")
      end
      true
    end

    def to_hash
      fields = %w(uri imgsize_x imgsize_y winsize_x winsize_y keepratio effect)
      Hash[fields.map{|f| [f, self.send(f)] }]
    end
  end
end
