module WebShot
  class InternalError < StandardError; end
  class InvalidURI < StandardError; end
  class ForbiddenURI < StandardError; end
  class URILoadFailed < StandardError; end
end
