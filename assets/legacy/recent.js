import {formatLink} from './util.js';

export function setupRecentTable() {
  $('#reviews').DataTable({
    processing: true,
    serverSide: false,
    ajax: $('#reviews').data('script'),
    columns: [
      {data: 'external_link'},
      {data: 'created_epoch'},
      {data: 'reviewed_epoch'},
      {data: 'name'},
      {data: 'state'},
      {data: 'result'},
      {data: 'login'},
      {data: 'checksum'}
    ],
    columnDefs: [
      {
        targets: 'link',
        render(data, type, row) {
          return formatLink(row);
        }
      },
      {
        targets: 'created',
        render(data, type, row) {
          if (type === 'display') {
            return `<span title="${row.created}">${$.timeago(new Date(data * 1000))}</span>`;
          }
          return data;
        }
      },
      {
        targets: 'reviewed',
        render(data, type, row) {
          if (type === 'display') {
            return `<span title="${row.reviewed}">${$.timeago(new Date(data * 1000))}</span>`;
          }
          return data;
        }
      },
      {
        targets: 'package',
        render(data, type) {
          if (type === 'display') {
            return `<a href='/search?q=${data}'>${data}</a>`;
          }
          return data;
        }
      },
      {
        targets: 'report',
        render(data, type, row) {
          if (!row.imported) {
            return '<i>not yet imported</i>';
          } else if (!row.unpacked) {
            return '<i>not yet unpacked</i>';
          } else if (!row.indexed) {
            return '<i>not yet indexed</i>';
          } else if (row.checksum) {
            return `<a href='/reviews/details/${row.id}'/>${row.checksum}</a>`;
          }
          return `<a href='/reviews/details/${row.id}'/>unpacked</a>`;
        }
      }
    ],
    order: [[2, 'desc']]
  });
}
