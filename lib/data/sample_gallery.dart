import '../models/gallery_image.dart';

// These bundled images are fallback/demo content. The real app normally shows
// device gallery content:// images after Android indexing has completed.
const sampleGalleryImages = [
  GalleryImage(
    id: 'dog-closeup',
    assetPath: 'assets/images/img8.jpg',
    title: 'Dark Companion Portrait',
    description:
        'A moody close-up portrait with a dark subject, warm indoor light, and soft texture.',
    date: 'Dec 24, 2023',
    location: 'Home Studio',
    tags: ['Pet', 'Portrait', 'Low light', 'Warm indoor'],
    matchPercent: 92,
  ),
  GalleryImage(
    id: 'orange-car',
    assetPath: 'assets/images/img1.jpg',
    title: 'Orange Road Machine',
    description:
        'A cinematic sports car shot on open asphalt under dramatic sunset clouds.',
    date: 'Nov 18, 2023',
    location: 'Open Road',
    tags: ['Car', 'Orange', 'Sunset', 'Speed'],
    matchPercent: 88,
  ),
  GalleryImage(
    id: 'dog-smile',
    assetPath: 'assets/images/img0.jpg',
    title: 'Happy Black Puppy',
    description:
        'A bright indoor portrait of a small black dog looking directly at the camera.',
    date: 'Nov 14, 2023',
    location: 'Living Room',
    tags: ['Pet', 'Selfie', 'Cute', 'Indoor'],
    matchPercent: 85,
  ),
  GalleryImage(
    id: 'coastal-scooter',
    assetPath: 'assets/images/img2.jpg',
    title: 'Coastal Scooter',
    description:
        'A quiet scooter scene beside water with storm clouds and muted tones.',
    date: 'Oct 29, 2023',
    location: 'Coastline',
    tags: ['Scooter', 'Clouds', 'Travel', 'Moody'],
    matchPercent: 83,
  ),
  GalleryImage(
    id: 'city-scooter',
    assetPath: 'assets/images/img3.jpg',
    title: 'Vintage Orange Scooter',
    description:
        'A street-side orange scooter with retro styling and shallow depth of field.',
    date: 'Oct 26, 2023',
    location: 'Tokyo, JP',
    tags: ['Scooter', 'Vintage', 'Orange', 'Street'],
    matchPercent: 80,
  ),
  GalleryImage(
    id: 'dark-scooter',
    assetPath: 'assets/images/img4.jpg',
    title: 'Urban Scooter Aesthetic',
    description:
        'A cool-toned scooter parked against a textured urban wall and shutter.',
    date: 'Oct 24, 2023',
    location: 'City District',
    tags: ['Urban', 'Vehicle', 'Cool tone', 'Street'],
    matchPercent: 78,
  ),
  GalleryImage(
    id: 'board-one',
    assetPath: 'assets/images/img5.jpg',
    title: 'Saved Visual Note',
    description:
        'A compact saved image with graphic edges and personal-board energy.',
    date: 'Oct 20, 2023',
    location: 'Gallery',
    tags: ['Board', 'Saved', 'Visual', 'Archive'],
    matchPercent: 76,
  ),
  GalleryImage(
    id: 'board-two',
    assetPath: 'assets/images/img6.jpg',
    title: 'Minimal Archive Frame',
    description:
        'A small collected visual with a quiet composition and neutral palette.',
    date: 'Oct 18, 2023',
    location: 'Gallery',
    tags: ['Archive', 'Minimal', 'Reference', 'Board'],
    matchPercent: 74,
  ),
  GalleryImage(
    id: 'board-three',
    assetPath: 'assets/images/img7.jpg',
    title: 'Collected Mood Reference',
    description:
        'A saved reference image for later visual clustering and retrieval.',
    date: 'Oct 16, 2023',
    location: 'Gallery',
    tags: ['Reference', 'Mood', 'Board', 'Saved'],
    matchPercent: 72,
  ),
];
