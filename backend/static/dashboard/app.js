/* Turflet admin panel behaviour (jQuery). */
$(function () {
  // CSRF for every AJAX POST
  $.ajaxSetup({ headers: { 'X-CSRFToken': window.CSRF, 'X-Requested-With': 'XMLHttpRequest' } });

  const icons = () => window.lucide && lucide.createIcons();
  icons();

  window.toast = function (msg, ok = true) {
    const $t = $('#toast');
    $t.text(msg).toggleClass('bg-red-700', !ok).toggleClass('bg-brand-ink', ok).removeClass('hidden').addClass('block');
    clearTimeout(window._toastT);
    window._toastT = setTimeout(() => $t.addClass('hidden').removeClass('block'), 2600);
  };

  // sidebar on mobile
  $('#menuBtn').on('click', () => { $('#sidebar').removeClass('-translate-x-full'); $('#backdrop').removeClass('hidden'); });
  $('#backdrop').on('click', () => { $('#sidebar').addClass('-translate-x-full'); $('#backdrop').addClass('hidden'); });

  $(document).on('click', '.flash-close', function () { $(this).closest('.flash').slideUp(150); });

  // confirm modal helper
  window.confirmAction = function (title, text, yesLabel) {
    return new Promise((resolve) => {
      $('#confirmTitle').text(title); $('#confirmText').text(text); $('#confirmYes').text(yesLabel || 'Delete');
      $('#confirmModal').removeClass('hidden').addClass('flex');
      const close = (v) => { $('#confirmModal').addClass('hidden').removeClass('flex'); $('#confirmYes,#confirmNo').off('click'); resolve(v); };
      $('#confirmYes').on('click', () => close(true));
      $('#confirmNo').on('click', () => close(false));
    });
  };

  // generic delete (rows and photos)
  $(document).on('click', '[data-delete-url]', async function (e) {
    e.preventDefault();
    const $btn = $(this);
    if (!(await confirmAction('Delete this item?', $btn.data('confirm') || 'This cannot be undone.'))) return;
    $.post($btn.data('delete-url'))
      .done(() => { $btn.closest('[data-row]').fadeOut(200, function () { $(this).remove(); }); toast('Deleted'); })
      .fail((x) => toast((x.responseJSON && x.responseJSON.message) || 'Could not delete', false));
  });

  // boolean toggles in tables
  $(document).on('click', '[data-toggle-url]', function (e) {
    e.preventDefault();
    const $b = $(this);
    $.post($b.data('toggle-url')).done((r) => {
      $b.text(r.value ? 'Yes' : 'No')
        .toggleClass('bg-green-100 text-green-800', r.value)
        .toggleClass('bg-slate-100 text-slate-500', !r.value);
    }).fail(() => toast('Could not update', false));
  });

  // live search + filters on list pages (replaces the table without a reload)
  const $list = $('#crudList');
  if ($list.length) {
    let t;
    const reload = (page) => {
      const params = $('#crudFilters').serializeArray().filter((p) => p.value !== '');
      if (page) params.push({ name: 'page', value: page });
      const qs = $.param(params);
      history.replaceState(null, '', '?' + qs);
      $list.addClass('opacity-60');
      $.get(location.pathname + '?partial=1&' + qs).done((html) => { $list.html(html).removeClass('opacity-60'); icons(); });
    };
    $('#crudFilters').on('input', 'input[name=q]', () => { clearTimeout(t); t = setTimeout(() => reload(), 300); });
    $('#crudFilters').on('change', 'select', () => reload());
    $('#crudFilters').on('submit', (e) => { e.preventDefault(); reload(); });
    $(document).on('click', '#crudList [data-page]', function (e) { e.preventDefault(); reload($(this).data('page')); });
  }

  // global search
  let gt;
  $('#globalSearch').on('input', function () {
    const q = $(this).val().trim();
    clearTimeout(gt);
    if (q.length < 2) return $('#globalResults').addClass('hidden');
    gt = setTimeout(() => {
      $.get('/admin-panel/search/', { q }).done((r) => {
        const $r = $('#globalResults').empty();
        if (!r.results.length) $r.append('<div class="px-4 py-3 text-sm text-brand-muted">No matches</div>');
        r.results.forEach((x) => {
          $r.append($('<a class="flex items-center justify-between px-4 py-2.5 text-sm hover:bg-brand-ground">')
            .attr('href', x.url).append($('<span class="truncate">').text(x.label))
            .append($('<span class="ml-3 text-xs text-brand-muted">').text(x.kind)));
        });
        $r.removeClass('hidden');
      });
    }, 250);
  });
  $(document).on('click', (e) => { if (!$(e.target).closest('#globalSearch,#globalResults').length) $('#globalResults').addClass('hidden'); });

  // image preview on file inputs
  $(document).on('change', '.js-image-input', function () {
    const f = this.files && this.files[0];
    if (!f) return;
    let $p = $(this).siblings('.js-preview');
    if (!$p.length) $p = $('<img class="js-preview mt-2 h-28 w-40 rounded-xl object-cover">').insertAfter(this);
    $p.attr('src', URL.createObjectURL(f));
  });

  // venue photo uploader (drag & drop + click)
  const $drop = $('#photoDrop');
  if ($drop.length) {
    const upload = (files) => {
      if (!files.length) return;
      const fd = new FormData();
      $.each(files, (_, f) => fd.append('images', f));
      $drop.find('.label').text('Uploading ' + files.length + ' photo(s)…');
      $.ajax({ url: $drop.data('url'), method: 'POST', data: fd, processData: false, contentType: false })
        .done((r) => {
          r.photos.forEach((p) => {
            $('#photoGrid').append(
              `<div data-row class="group relative"><img src="${p.url}" class="h-32 w-full rounded-xl object-cover" alt="">
               <button type="button" data-delete-url="${$drop.data('url')}${p.id}/delete/" class="absolute right-2 top-2 hidden rounded-lg bg-white/95 px-2 py-1 text-xs font-semibold text-red-700 group-hover:block">Delete</button></div>`);
          });
          toast('Uploaded');
        })
        .fail(() => toast('Upload failed', false))
        .always(() => $drop.find('.label').text('Drop photos here or click to upload'));
    };
    $drop.on('click', () => $('#photoInput').trigger('click'));
    $('#photoInput').on('change', function () { upload(this.files); this.value = ''; });
    $drop.on('dragover', (e) => { e.preventDefault(); $drop.addClass('border-brand bg-brand-50'); });
    $drop.on('dragleave drop', (e) => { e.preventDefault(); $drop.removeClass('border-brand bg-brand-50'); });
    $drop.on('drop', (e) => upload(e.originalEvent.dataTransfer.files));
  }

  // AJAX action buttons (booking check-in etc.)
  $(document).on('click', '[data-action-url]', async function (e) {
    e.preventDefault();
    const $b = $(this);
    if ($b.data('confirm') && !(await confirmAction($b.data('confirm-title') || 'Please confirm', $b.data('confirm'), $b.data('yes') || 'Confirm'))) return;
    $b.prop('disabled', true).addClass('opacity-60');
    $.post($b.data('action-url'), $b.data('payload') || {})
      .done((r) => { toast(r.message || 'Done'); setTimeout(() => location.reload(), 600); })
      .fail((x) => { toast((x.responseJSON && x.responseJSON.message) || 'Failed', false); $b.prop('disabled', false).removeClass('opacity-60'); });
  });
});
