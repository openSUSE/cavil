export function setupProductTable() {
  const dt = $('#reviews').DataTable({
    processing: true,
    serverSide: false,
    ajax: $('#reviews').data('script'),
    columns: [{data: 'name'}, {data: 'state'}, {data: 'checksum'}],
    columnDefs: [
      {
        targets: 'package',
        render(data, type, row) {
          if (type === 'display') {
            return `<a href='/search?q=${data}' target='_blank'>${data}</a>`;
          }
          return data;
        }
      },
      {
        targets: 'report',
        render(data, type, row) {
          if (row.checksum) {
            return `<a href='/reviews/details/${row.id}' target='_blank'>${row.checksum}</a>`;
          }
          return `<a href='/reviews/details/${row.id}' target='_blank'>not available</a>`;
        }
      }
    ],
    order: [[0, 'asc']]
  });
}
