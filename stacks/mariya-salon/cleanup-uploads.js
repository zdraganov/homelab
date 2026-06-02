const { PrismaClient } = require('@prisma/client');
const fs = require('fs');

const p = new PrismaClient();

p.galleryImage.findMany().then(imgs => {
  const known = new Set(imgs.map(i => i.url.replace('/uploads/', '')));
  const files = fs.readdirSync('/uploads').filter(f => f !== '.' && f !== '..');
  const orphans = files.filter(f => !known.has(f));
  orphans.forEach(f => {
    fs.unlinkSync('/uploads/' + f);
    console.log('deleted:', f);
  });
  console.log('done, removed', orphans.length, 'orphan files');
  p.$disconnect();
});
