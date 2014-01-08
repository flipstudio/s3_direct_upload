#= require jquery-fileupload/basic
#= require jquery-fileupload/vendor/tmpl
#= require spark-md5.min.js

$ = jQuery

$.fn.S3Uploader = (options) ->

  # support multiple elements
  if @length > 1
    @each ->
      $(this).S3Uploader options

    return this

  $uploadForm = this

  settings =
    path: ''
    additional_data: null
    before_add: null
    remove_completed_progress_bar: true
    remove_failed_progress_bar: false
    progress_bar_target: null
    click_submit_target: null
    send_fingerprint: false

  $.extend settings, options

  current_files = []
  forms_for_submit = []
  if settings.click_submit_target
    settings.click_submit_target.click ->
      form.submit() for form in forms_for_submit
      false

  setUploadForm = ->
    $uploadForm.fileupload

      add: (e, data) ->
        file = data.files[0]
        file.unique_id = Math.random().toString(36).substr(2,16)

        unless settings.before_add and not settings.before_add(file)
          current_files.push data
          data.context = $($.trim(tmpl("template-upload", file))) if $('#template-upload').length > 0
          $(data.context).appendTo(settings.progress_bar_target || $uploadForm)
          if settings.click_submit_target
            forms_for_submit.push data
          else
            data.submit()

      start: (e) ->
        $uploadForm.trigger("s3_uploads_start", [e])

      progress: (e, data) ->
        if data.context
          progress = parseInt(data.loaded / data.total * 100, 10)
          data.context.find('.bar').css('width', progress + '%')

      done: (e, data) ->
        if settings.send_fingerprint
          compute_fingerprint(data)
        else
          finish(data)

      fail: (e, data) ->
        content = build_content_object $uploadForm, data.files[0], data.result
        content.error_thrown = data.errorThrown

        data.context.remove() if data.context && settings.remove_failed_progress_bar # remove progress bar
        $uploadForm.trigger("s3_upload_failed", [content])

      formData: (form) ->
        data = form.serializeArray()
        fileType = ""
        if "type" of @files[0]
          fileType = @files[0].type
        data.push
          name: "Content-Type"
          value: fileType

        data[1].value = settings.path + data[1].value #the key
        data

  build_content_object = ($uploadForm, file, result) ->
    content = {}
    if result # Use the S3 response to set the URL to avoid character encodings bugs
      content.url      = $(result).find("Location").text()
      content.filepath = $('<a />').attr('href', content.url)[0].pathname
      content.key      = $(result).find("Key").text()
    else # IE <= 9 return a null result object so we use the file object instead
      domain           = $uploadForm.attr('action')
      content.filepath = settings.path + $uploadForm.find('input[name=key]').val().replace('/${filename}', '')
      content.url      = domain + content.filepath + '/' + encodeURIComponent(file.name)
      content.key      = $uploadForm.find('input[name=key]').val().replace('${filename}', file.name)

    content.filename    = file.name
    content.filesize    = file.size if 'size' of file
    content.filetype    = file.type if 'type' of file
    content.unique_id   = file.unique_id if 'unique_id' of file
    content.fingerprint = result.fingerprint if settings.send_fingerprint 
    content = $.extend content, settings.additional_data if settings.additional_data
    content

  compute_fingerprint = (data) ->
    file = data.files[0]
    blob_slice = File::slice or File::mozSlice or File::webkitSlice
    chunk_size = 524288
    chunks = Math.ceil(file.size / chunk_size)
    current_chunk = 0
    spark = new SparkMD5.ArrayBuffer()

    set_progress = ->
      progress = parseInt(current_chunk / chunks * 100, 10)
      data.context.find('.bar').css('width', progress + '%')

    append_chunk = (e) ->
      spark.append e.target.result
      current_chunk++
      set_progress()

      if current_chunk < chunks
        read_chunk()
      else
        data.result.fingerprint = spark.end()
        finish(data)

    read_chunk = ->
      file_reader = new FileReader()
      file_reader.onload = append_chunk
      
      start = current_chunk * chunk_size
      end = (if ((start + chunk_size) >= file.size) then file.size else start + chunk_size)
      
      file_reader.readAsArrayBuffer blob_slice.call(file, start, end)

    set_progress()
    setTimeout (->
      read_chunk()
    ), 1000

  finish = (data) ->
    content = build_content_object $uploadForm, data.files[0], data.result

    to = $uploadForm.data('post')
    if to
      content[$uploadForm.data('as')] = content.url

      $.ajax
        type: 'POST'
        url: to
        data: content
        beforeSend: ( xhr, settings )       -> $uploadForm.trigger( 'ajax:beforeSend', [xhr, settings] )
        complete:   ( xhr, status )         -> $uploadForm.trigger( 'ajax:complete', [xhr, status] )
        success:    ( data, status, xhr )   -> $uploadForm.trigger( 'ajax:success', [data, status, xhr] )
        error:      ( xhr, status, error )  -> $uploadForm.trigger( 'ajax:error', [xhr, status, error] )

      # $.post(to, content)
    else
      form = $uploadForm.data('form')
      if form
        hidden_field = (name, value) -> $('<input type="hidden">').attr('name', name).attr('value', value)
        
        parentNode = $('#' + form)
        as = $uploadForm.data('as')

        parentNode.append hidden_field(as + '[file_path]', content.key)
        parentNode.append hidden_field(as + '[file_size]', content.filesize)
        parentNode.append hidden_field(as + '[content_type]', content.filetype)
        parentNode.append hidden_field(as + '[fingerprint]', content.fingerprint) if content.fingerprint
    
    data.context.remove() if data.context && settings.remove_completed_progress_bar # remove progress bar
    $uploadForm.trigger("s3_upload_complete", [content])

    current_files.splice($.inArray(data, current_files), 1) # remove that element from the array
    $uploadForm.trigger("s3_uploads_complete", [content]) unless current_files.length

  #public methods
  @initialize = ->
    setUploadForm()
    this

  @path = (new_path) ->
    settings.path = new_path

  @additional_data = (new_data) ->
    settings.additional_data = new_data

  @initialize()
