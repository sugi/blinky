img_update = (elem) ->
  elem.src = elem.src + ";d=" + new Date().getTime();
gen_check_update_func = (elem) ->
  ->
    $elem = $(elem)
    $.ajax
      url: $(elem).data('status-uri')
      method: 'GET'
      dataType: 'json'
      success: (data, xhr, status) ->
        if data['status'] == "stable"
          img_update(elem)
        else
          setTimeout gen_check_update_func(elem), 5000
$ ->
  $('.ss-image').each (index) ->
    setTimeout gen_check_update_func(this), 3000
